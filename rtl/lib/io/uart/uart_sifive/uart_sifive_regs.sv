/* UartSifive's registers: SiFive's UART register map (UartSifivePkg) behind the register port,
 * wiring only.
 *
 * The FIFOs, the engine and the watermarks are outside (the UartSifive top); this is the map.
 * txdata: a write of its byte 0 pushes the byte into the transmit FIFO (tx_push, tx_data; the
 * FIFO drops it when full, as SiFive's: software reads full first, or loses the byte); a read
 * gives full. rxdata: a read pops the receive FIFO (rx_pop, in the clock the read is taken:
 * once per read, RegPortTarget's rule) and gives the byte popped and empty; the data is 0 when
 * empty. txctrl, rxctrl, ie, div: StrbRegs, written byte by byte; their fields are outputs.
 * ip: an input (UartWatermark), read only. A reserved address (0x1c and above) reads 0, a write
 * there is ignored; reserved bits read 0. div resets to DIV_RST (SiFive leaves the value to the
 * platform: its boot rate), every other field to 0 (nothing sent or received, no interrupt).
 *
 *              register port (req_*, rsp_*)
 *                        |
 *                  RegPortTarget
 *                        |  acc_rd / acc_wr, acc_addr, acc_wdata, acc_wstrb
 *       Decoder of the word address (the registers are the words 0 to 6, in order)
 *                        |
 *   +--------+-----------+-----------+------------+-----------+
 *   |txdata  |rxdata     |txctrl     |rxctrl      |ie         |div
 *   v        v           v           v            v           v
 * tx_push  rx_pop    StrbReg      StrbReg      StrbReg     StrbReg
 * tx_data            txen, nstop, rxen, rxcnt  ie          div
 *                    txcnt
 *
 *  reads: MuxOneHot of {full}, {empty, rx_data}, txctrl, rxctrl, ie, ip, div --> rd_data
 *
 * One file for the behave and the struct library: the parts of the library it is built with
 * give the version.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "dark_circuit_assert.svh"

module UartSifiveRegs import UartSifivePkg::*; #(
    parameter  [DIV_BITS-1:0] DIV_RST = '1,         // div after reset (the platform's boot rate)
    localparam ADDR_WIDTH = ADDR_BITS,              // bits of req_addr: the 4 KiB map
    localparam DATA_WIDTH = 32,                     // bits of a register access
    localparam STRB_WIDTH = DATA_WIDTH / 8
)(
    input  wire                  clk,
    input  wire                  rst_n,     // synchronous reset, active low
    // Register port
    input  wire                  req_valid,
    output wire                  req_ready,
    input  wire                  req_we,    // 1 write, 0 read
    input  wire [ADDR_WIDTH-1:0] req_addr,  // byte address inside the UART
    input  wire [DATA_WIDTH-1:0] req_wdata,
    input  wire [STRB_WIDTH-1:0] req_wstrb, // bytes written
    output wire                  rsp_valid, // the answer to a read
    output wire [DATA_WIDTH-1:0] rsp_rdata,
    // The FIFOs
    output wire                  tx_push,   // a byte for the transmit FIFO now
    output wire [7:0]            tx_data,
    input  wire                  tx_full,
    output wire                  rx_pop,    // the receive FIFO's oldest byte is read now
    input  wire [7:0]            rx_data,   // that byte (first-word fall-through)
    input  wire                  rx_empty,
    // The fields
    output wire                  txen,
    output wire                  nstop,     // 2 stop bits
    output wire [CNT_BITS-1:0]   txcnt,
    output wire                  rxen,
    output wire [CNT_BITS-1:0]   rxcnt,
    output wire [1:0]            ie,        // [1] rxwm, [0] txwm
    output wire [DIV_BITS-1:0]   div,
    input  wire [1:0]            ip         // [1] rxwm, [0] txwm
);
    localparam CB = CNT_LSB / 8;                    // the byte of txcnt and rxcnt
    localparam CZ = DATA_WIDTH - CNT_LSB - CNT_BITS; // zeros above them

    // The Decoder's select is the word address and the fields are where the ports say.
    `DC_STATIC_ASSERT(a_map, TXDATA == 0 && RXDATA == 4 && TXCTRL == 8 && RXCTRL == 12 &&
                             IE == 16 && IP == 20 && DIV == 24 && N_REGS == 7 &&
                             FLAG_BIT == DATA_WIDTH - 1 && EN_BIT == 0 && NSTOP_BIT == 1 &&
                             TXWM_BIT == 0 && RXWM_BIT == 1 && CNT_LSB % 8 + CNT_BITS <= 8)

    wire                  acc_rd;       // a read is taken now
    wire                  acc_wr;       // a write is taken now
    // Bits 1:0 pick a byte: the strobes do that.
    /* verilator lint_off UNUSEDSIGNAL */
    wire [ADDR_WIDTH-1:0] acc_addr;
    /* verilator lint_on UNUSEDSIGNAL */
    // Only the bits and bytes of the fields are written.
    /* verilator lint_off UNUSEDSIGNAL */
    wire [DATA_WIDTH-1:0] acc_wdata;
    wire [STRB_WIDTH-1:0] acc_wstrb;
    /* verilator lint_on UNUSEDSIGNAL */
    wire [DATA_WIDTH-1:0] rd_data;      // the selected register
    wire                  in_regs;      // acc_addr is below 0x20
    // Word 7 (0x1c) is reserved.
    /* verilator lint_off UNUSEDSIGNAL */
    wire [7:0]            word;         // the word address, one-hot
    /* verilator lint_on UNUSEDSIGNAL */
    wire [N_REGS-1:0]     sel;          // register r (offset 4r) is accessed now
    wire [N_REGS-1:0]     wr;           // ... written now
    wire                  rx_empty_n;
    wire [7:0]            rx_shown;     // rx_data, 0 when empty
    wire [N_REGS-1:0][DATA_WIDTH-1:0] words;    // every register, read

    // Register port and decode.
    RegPortTarget #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)) u_reg_port_target(
        .clk, .rst_n, .req_valid, .req_ready, .req_we, .req_addr, .req_wdata, .req_wstrb,
        .rsp_valid, .rsp_rdata, .hold(1'b0), .acc_rd, .acc_wr, .acc_addr, .acc_wdata,
        .acc_wstrb, .rd_data);

    // @kb: rtl/lib/io/uart/uart_sifive/design
    NorReduce #(ADDR_WIDTH - 5) u_nor_reduce_in_regs(.in(acc_addr[ADDR_WIDTH-1:5]), .out(in_regs));
    Decoder #(.SIZE(3)) u_decoder_word(.in(acc_addr[4:2]), .en(in_regs), .out(word));
    assign sel = word[N_REGS-1:0];
    And2 #(N_REGS) u_and2_wr(.in1({N_REGS{acc_wr}}), .in2(sel), .out(wr));

    // txdata: a write of byte 0 pushes it; rxdata: a read pops, in the clock it is taken.
    And2 #(1) u_and2_tx_push(.in1(wr[TXDATA / 4]), .in2(acc_wstrb[0]), .out(tx_push));
    assign tx_data = acc_wdata[7:0];
    And2 #(1) u_and2_rx_pop(.in1(acc_rd), .in2(sel[RXDATA / 4]), .out(rx_pop));

    // The fields, byte by byte: txen, nstop, rxen, ie in byte 0, the counts in byte CB, div in
    // bytes 1:0.
    StrbReg #(.WIDTH(2)) u_strb_reg_txctrl(
        .clk, .rst_n, .we(wr[TXCTRL / 4]), .wstrb(acc_wstrb[0]), .wdata(acc_wdata[1:0]),
        .q({nstop, txen}));
    StrbReg #(.WIDTH(CNT_BITS)) u_strb_reg_txcnt(
        .clk, .rst_n, .we(wr[TXCTRL / 4]), .wstrb(acc_wstrb[CB]),
        .wdata(acc_wdata[CNT_LSB +: CNT_BITS]), .q(txcnt));
    StrbReg #(.WIDTH(1)) u_strb_reg_rxen(
        .clk, .rst_n, .we(wr[RXCTRL / 4]), .wstrb(acc_wstrb[0]), .wdata(acc_wdata[0]),
        .q(rxen));
    StrbReg #(.WIDTH(CNT_BITS)) u_strb_reg_rxcnt(
        .clk, .rst_n, .we(wr[RXCTRL / 4]), .wstrb(acc_wstrb[CB]),
        .wdata(acc_wdata[CNT_LSB +: CNT_BITS]), .q(rxcnt));
    StrbReg #(.WIDTH(2)) u_strb_reg_ie(
        .clk, .rst_n, .we(wr[IE / 4]), .wstrb(acc_wstrb[0]), .wdata(acc_wdata[1:0]), .q(ie));
    StrbReg #(.WIDTH(DIV_BITS), .RST_VAL(DIV_RST)) u_strb_reg_div(
        .clk, .rst_n, .we(wr[DIV / 4]), .wstrb(acc_wstrb[DIV_BITS / 8 - 1:0]),
        .wdata(acc_wdata[DIV_BITS-1:0]), .q(div));

    // Reads: every register by its select; a reserved address selects none (0).
    Inv  #(1) u_inv_rx_empty(.in(rx_empty), .out(rx_empty_n));
    And2 #(8) u_and2_rx_shown(.in1(rx_data), .in2({8{rx_empty_n}}), .out(rx_shown));
    assign words[TXDATA / 4] = {tx_full, {(DATA_WIDTH - 1){1'b0}}};
    assign words[RXDATA / 4] = {rx_empty, {(DATA_WIDTH - 9){1'b0}}, rx_shown};
    assign words[TXCTRL / 4] = {{CZ{1'b0}}, txcnt, {(CNT_LSB - 2){1'b0}}, nstop, txen};
    assign words[RXCTRL / 4] = {{CZ{1'b0}}, rxcnt, {(CNT_LSB - 1){1'b0}}, rxen};
    assign words[IE / 4]     = {{(DATA_WIDTH - 2){1'b0}}, ie};
    assign words[IP / 4]     = {{(DATA_WIDTH - 2){1'b0}}, ip};
    assign words[DIV / 4]    = {{(DATA_WIDTH - DIV_BITS){1'b0}}, div};
    MuxOneHot #(.N(N_REGS), .WIDTH(DATA_WIDTH)) u_mux_one_hot_rd(
        .in(words), .sel, .out(rd_data));

endmodule

/* UartSifive: a UART with SiFive's register map (UartSifivePkg) behind the register port, the
 * device top, wiring only.
 *
 * The parts: UartSifiveRegs (the map), two Fifos of 8 bytes, UartTx and UartRx (the serial
 * engine, 8 data bits, no parity, nstop for the transmitter), one TickGen for both and
 * UartWatermark (the interrupt). The bit rate is f_clk / (div + 1), SiFive's convention: the
 * TickGen ticks 16 times a bit, every (div + 1) / 16 clocks, as a fixed-point number with 4
 * fractional bits, div - 15 (exact over a bit: every bit is div + 1 clocks); div must be 15
 * or more (a tick in every clock at most). The tick runs whatever txen and rxen are, so a
 * frame on the line finishes whatever software does; a write of div restarts it (TickGen's en
 * is 0 for the clock after the write), so the new rate starts at once, not after a period of
 * the old one (4096 clocks for the reset value all ones).
 *  - Transmit: a write of txdata pushes into the transmit FIFO (dropped when full); with txen
 *    the oldest byte goes to UartTx when it takes one. txen = 0 keeps the bytes in the FIFO
 *    (the frame on the line finishes).
 *  - Receive: UartRx always follows the line; with rxen every byte it receives goes into the
 *    receive FIFO (dropped when full, as SiFive's: no overrun flag), without rxen it is
 *    dropped, so enabling it in the middle of a frame gives no broken byte. SiFive's UART
 *    reports no framing errors: a byte with a bad stop bit is kept like the others.
 *  - Interrupt: irq = (tx FIFO count < txcnt and ie.txwm) or (rx FIFO count > rxcnt and
 *    ie.rxwm), a level from flops (UartWatermark).
 *
 *              register port (req_*, rsp_*)
 *                        |
 *                 UartSifiveRegs --- div --> RippleCarryAdder (- 15) --> TickGen --> tick
 *                        |  div_wr --> DffSyncRst --> Inv --> en ---------^
 *     tx_push, tx_data |  ^ tx_full       rx_pop |  ^ rx_data, rx_empty
 *                      v  |                      v  |
 *                  Fifo tx (8)               Fifo rx (8) <-- out_valid & rxen
 *                      |  data_out, empty           ^ out_data
 *       txen & !empty  v                            |
 *                    UartTx (tick, nstop) --> tx   UartRx (tick) <-- rx
 *     counts, txcnt, rxcnt, ie --> UartWatermark --> ip (to the regs), irq
 *
 * One file for the behave and the struct library: the parts of the library it is built with
 * give the version.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "dark_circuit_assert.svh"

module UartSifive import UartSifivePkg::*; #(
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
    // Pins and the interrupt
    output wire                  tx,        // the serial line out
    input  wire                  rx,        // the serial line in: a pin, asynchronous to clk
    output wire                  irq        // a level: a PLIC source
);
    localparam CW = FIFO_ADDR + 1;                  // bits of a FIFO's count: 0 to 8
    // The tick's period in clocks with 4 fractional bits: (div + 1) / 16 - 1 = (div - 15) / 16.
    localparam FRAC_BITS = $clog2(UartPkg::OVERSAMPLE);
    localparam [DIV_BITS-1:0] MINUS_15 = DIV_BITS'(-(UartPkg::OVERSAMPLE - 1));
    // The frame: 8 data bits, no parity (SiFive's).
    localparam UartPkg::data_bits_t DATA_BITS_8 = 2'(8 - 5);
    localparam UartPkg::parity_e    NO_PARITY   = UartPkg::PARITY_NONE;

    wire                tx_push;        // the regs
    wire [7:0]          tx_data;
    wire                rx_pop;
    wire                txen, nstop, rxen;
    wire [CNT_BITS-1:0] txcnt, rxcnt;
    wire [1:0]          ie, ip;
    wire [DIV_BITS-1:0] div;
    wire                div_wr;         // div is written now
    wire                div_new;        // ... was written at the last edge: restart the tick
    wire                tick_en;
    wire                tx_full;        // the transmit FIFO
    wire                tx_empty;
    wire                tx_empty_n;
    wire [7:0]          tx_head;        // its oldest byte
    wire [CW-1:0]       tx_count;
    wire                rx_empty;       // the receive FIFO
    wire [7:0]          rx_head;
    wire [CW-1:0]       rx_count;
    wire [DIV_BITS-1:0] tick_div;       // div - 15
    wire                tick;
    wire                tx_valid;       // a byte for UartTx: txen and the FIFO not empty
    wire                tx_ready;
    wire                tx_take;        // UartTx takes the oldest byte now
    wire                rx_valid;       // UartRx received a byte now
    wire [7:0]          rx_byte;
    wire                rx_keep;        // ... and rxen: into the receive FIFO
    // Not used: SiFive's UART has no overrun or error flags, the FIFO thresholds are the
    // watermarks, UartTx's busy is in its in_ready, div - 15 never needs a carry.
    /* verilator lint_off UNUSEDSIGNAL */
    wire                rx_full;
    wire                tx_almost_full, tx_almost_empty, rx_almost_full, rx_almost_empty;
    wire                frame_err, parity_err;
    wire                tx_busy;
    wire                co_div;
    /* verilator lint_on UNUSEDSIGNAL */

    // @kb: rtl/lib/io/uart/uart_sifive/top
    UartSifiveRegs #(.DIV_RST(DIV_RST)) u_regs(
        .clk, .rst_n, .req_valid, .req_ready, .req_we, .req_addr, .req_wdata, .req_wstrb,
        .rsp_valid, .rsp_rdata, .tx_push, .tx_data, .tx_full, .rx_pop, .rx_data(rx_head),
        .rx_empty, .txen, .nstop, .txcnt, .rxen, .rxcnt, .ie, .div, .div_wr, .ip);

    // The bit timing: 16 ticks a bit, for both directions; restarted with a new div (TickGen
    // reloads while en is 0, in the clock the new value is there).
    RippleCarryAdder #(DIV_BITS) u_ripple_carry_adder_div(
        .in1(div), .in2(MINUS_15), .ci(1'b0), .co(co_div), .sum(tick_div));
    DffSyncRst #(.WIDTH(1)) u_dff_sync_rst_div_new(.clk, .rst_n, .in(div_wr), .out(div_new));
    Inv  #(1) u_inv_tick_en(.in(div_new), .out(tick_en));
    TickGen #(.WIDTH(DIV_BITS), .FRAC_BITS(FRAC_BITS)) u_tick_gen(
        .clk, .rst_n, .en(tick_en), .div(tick_div), .tick);

    // Transmit: the FIFO into UartTx while txen.
    Fifo #(.ADDR_WIDTH(FIFO_ADDR), .DATA_WIDTH(8)) u_fifo_tx(
        .clk, .rst_n, .write(tx_push), .data_in(tx_data), .read(tx_take), .data_out(tx_head),
        .empty(tx_empty), .full(tx_full), .count(tx_count), .almost_full(tx_almost_full),
        .almost_empty(tx_almost_empty));
    Inv  #(1) u_inv_tx_empty(.in(tx_empty), .out(tx_empty_n));
    And2 #(1) u_and2_tx_valid(.in1(txen), .in2(tx_empty_n), .out(tx_valid));
    And2 #(1) u_and2_tx_take(.in1(tx_valid), .in2(tx_ready), .out(tx_take));
    UartTx u_uart_tx(
        .clk, .rst_n, .tick, .data_bits(DATA_BITS_8), .parity(NO_PARITY), .stop2(nstop),
        .in_valid(tx_valid), .in_ready(tx_ready), .in_data(tx_head), .tx, .busy(tx_busy));

    // Receive: UartRx into the FIFO while rxen.
    UartRx u_uart_rx(
        .clk, .rst_n, .tick, .data_bits(DATA_BITS_8), .parity(NO_PARITY), .rx,
        .out_valid(rx_valid), .out_data(rx_byte), .frame_err, .parity_err);
    And2 #(1) u_and2_rx_keep(.in1(rx_valid), .in2(rxen), .out(rx_keep));
    Fifo #(.ADDR_WIDTH(FIFO_ADDR), .DATA_WIDTH(8)) u_fifo_rx(
        .clk, .rst_n, .write(rx_keep), .data_in(rx_byte), .read(rx_pop), .data_out(rx_head),
        .empty(rx_empty), .full(rx_full), .count(rx_count), .almost_full(rx_almost_full),
        .almost_empty(rx_almost_empty));

    // The interrupt.
    UartWatermark #(.COUNT_WIDTH(CW), .LEVEL_WIDTH(CNT_BITS)) u_uart_watermark(
        .tx_count, .tx_level(txcnt), .rx_count, .rx_level(rxcnt), .ie, .ip, .irq);

    // 16 ticks a bit need a bit of 16 clocks at least, while the UART is used.
    `DC_ASSERT(a_div_min, !(txen || rxen) || div >= DIV_BITS'(UartPkg::OVERSAMPLE - 1))

endmodule

/* DmaSifive's registers: SiFive's PDMA register map (DmaSifivePkg) for N_CHANNELS channels
 * behind the register port, wiring only.
 *
 * Channel c's registers are at c * 0x1000 (DmaSifiveChannelRegs, see there); its 16 words
 * are the offsets 0x000 to 0x01c and 0x100 to 0x11c, word {offset[8], offset[4:2]}. Any other
 * offset, and a channel number of N_CHANNELS or more, reads 0, a write there is ignored.
 * Reads have no side effects (hold 0). The channels control DmaEngine's channels (start,
 * stop; busy, done, the Exec registers) and give two interrupts each: irq[2c] done, irq[2c+1]
 * error. error_ev is a transfer error of channel c (none yet: the library's memory channel
 * has no error answer).
 *
 *              register port (req_*, rsp_*)
 *                        |
 *                  RegPortTarget
 *                        |  acc_wr, acc_addr, acc_wdata, acc_wstrb
 *     Decoder of the channel (acc_addr[ADDR_BITS-1:12]), Decoder of the word
 *                        |  wr[c][w], sel[c][w]
 *     DmaSifiveChannelRegs c (0 .. N_CHANNELS-1) <--> DmaEngine channel c; irq[2c+1:2c]
 *                        |  words[c][w]
 *  reads: MuxOneHot of every channel's words --> rd_data
 *
 * One file for the behave and the struct library: the parts of the library it is built with
 * give the version.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "dark_circuit_assert.svh"

module DmaSifiveRegs import DmaSifivePkg::*; #(
    parameter  N_CHANNELS = 4,                      // 1 or more
    parameter  ADDR_WIDTH = 32,                     // the memory's byte address, 64 at most
    parameter  LEN_WIDTH  = 32,                     // bits of a byte count, 64 at most
    parameter  LOG_BEAT   = 3,                      // log2 of the mover's beat in bytes
    localparam N          = N_CHANNELS,
    localparam CH_BITS    = (N > 1) ? $clog2(N) : 0,
    localparam ADDR_BITS  = CHAN_BITS + CH_BITS,    // bits of req_addr
    localparam DATA_WIDTH = 32,
    localparam STRB_WIDTH = DATA_WIDTH / 8
)(
    input  wire                         clk,
    input  wire                         rst_n,      // synchronous reset, active low
    // Register port
    input  wire                         req_valid,
    output wire                         req_ready,
    input  wire                         req_we,     // 1 write, 0 read
    input  wire [ADDR_BITS-1:0]         req_addr,   // byte address inside the DMA
    input  wire [DATA_WIDTH-1:0]        req_wdata,
    input  wire [STRB_WIDTH-1:0]        req_wstrb,  // bytes written
    output wire                         rsp_valid,  // the answer to a read
    output wire [DATA_WIDTH-1:0]        rsp_rdata,
    // DmaEngine's channels
    output wire [N-1:0]                 start,
    output wire [N-1:0][ADDR_WIDTH-1:0] start_src,
    output wire [N-1:0][ADDR_WIDTH-1:0] start_dst,
    output wire [N-1:0][LEN_WIDTH-1:0]  start_len,
    output wire [N-1:0]                 stop,
    input  wire [N-1:0]                 busy,
    input  wire [N-1:0]                 done,
    input  wire [N-1:0]                 error_ev,   // a transfer error of channel c
    input  wire [N-1:0][ADDR_WIDTH-1:0] cur_src,
    input  wire [N-1:0][ADDR_WIDTH-1:0] cur_dst,
    input  wire [N-1:0][LEN_WIDTH-1:0]  left,
    // Interrupts: 2c done, 2c + 1 error of channel c (levels)
    output wire [2*N-1:0]               irq
);
    `DC_STATIC_ASSERT(a_channels, N_CHANNELS >= 1)

    // A read has no side effect here: only RegPortTarget uses it.
    /* verilator lint_off UNUSEDSIGNAL */
    wire                       acc_rd;
    /* verilator lint_on UNUSEDSIGNAL */
    wire                       acc_wr;
    // Bits 1:0 pick a byte: the strobes do that.
    /* verilator lint_off UNUSEDSIGNAL */
    wire [ADDR_BITS-1:0]       acc_addr;
    /* verilator lint_on UNUSEDSIGNAL */
    wire [DATA_WIDTH-1:0]      acc_wdata;
    wire [STRB_WIDTH-1:0]      acc_wstrb;
    wire [DATA_WIDTH-1:0]      rd_data;
    wire                       in_map;          // the offset is one of the 16 words
    wire [15:0]                word;            // ... which, one-hot
    // Channel numbers of N_CHANNELS or more select nothing.
    /* verilator lint_off UNUSEDSIGNAL */
    wire [(1 << CH_BITS)-1:0]  chan;            // the channel, one-hot
    /* verilator lint_on UNUSEDSIGNAL */
    wire [N-1:0][15:0]         sel;             // word w of channel c is accessed now
    wire [N-1:0][15:0]         wr;              // ... written now
    wire [N-1:0][15:0][31:0]   words;           // every word, read

    RegPortTarget #(.ADDR_WIDTH(ADDR_BITS), .DATA_WIDTH(DATA_WIDTH)) u_reg_port_target(
        .clk, .rst_n, .req_valid, .req_ready, .req_we, .req_addr, .req_wdata, .req_wstrb,
        .rsp_valid, .rsp_rdata, .hold(1'b0), .acc_rd, .acc_wr, .acc_addr, .acc_wdata,
        .acc_wstrb, .rd_data);

    // @kb: rtl/lib/block/dma/design
    NorReduce #(6) u_nor_reduce_in_map(.in({acc_addr[11:9], acc_addr[7:5]}), .out(in_map));
    Decoder #(.SIZE(4)) u_decoder_word(.in({acc_addr[8], acc_addr[4:2]}), .en(in_map),
                                       .out(word));
    if (N > 1) begin: g_chan
        Decoder #(.SIZE(CH_BITS)) u_decoder_chan(.in(acc_addr[ADDR_BITS-1:CHAN_BITS]),
                                                 .en(1'b1), .out(chan));
    end else begin: g_one
        assign chan = 1'b1;
    end

    for (genvar c = 0; c < N; c++) begin: g_channel
        And2 #(16) u_and2_sel(.in1(word), .in2({16{chan[c]}}), .out(sel[c]));
        And2 #(16) u_and2_wr(.in1(sel[c]), .in2({16{acc_wr}}), .out(wr[c]));
        DmaSifiveChannelRegs #(.ADDR_WIDTH(ADDR_WIDTH), .LEN_WIDTH(LEN_WIDTH),
                               .LOG_BEAT(LOG_BEAT)) u_channel_regs(
            .clk, .rst_n, .wr(wr[c]), .wdata(acc_wdata), .wstrb(acc_wstrb), .words(words[c]),
            .start(start[c]), .start_src(start_src[c]), .start_dst(start_dst[c]),
            .start_len(start_len[c]), .stop(stop[c]), .busy(busy[c]), .done_ev(done[c]),
            .err_ev(error_ev[c]), .cur_src(cur_src[c]), .cur_dst(cur_dst[c]), .left(left[c]),
            .irq_done(irq[2 * c]), .irq_err(irq[2 * c + 1]));
    end

    // Reads: every word by its select; no word selected reads 0.
    MuxOneHot #(.N(16 * N), .WIDTH(DATA_WIDTH)) u_mux_one_hot_rd(
        .in(words), .sel(sel), .out(rd_data));

endmodule

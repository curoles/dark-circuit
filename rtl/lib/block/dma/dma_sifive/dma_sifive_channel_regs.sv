/* The registers of one DmaSifive channel (DmaSifivePkg) and their control of a DMA channel
 * (DmaEngine's start and stop), wiring only.
 *
 * The 16 words of the channel are indexed by {offset[8], offset[4:2]}: 0 Control, 1
 * NextConfig, 2-7 NextBytes, NextDestination, NextSource (low, high), 8 reserved, 9
 * ExecConfig, 10-15 ExecBytes, ExecDestination, ExecSource (low, high). wr[w] is "word w is
 * written now" (with wdata, wstrb); words[w] is word w as read. Control:
 *  - claim: a write sets or clears it, but it stays 1 while run is 1; setting it (0 to 1)
 *    clears the Next registers, done and error. Writing 1 again clears nothing (Linux writes
 *    claim with every run).
 *  - run: writing 1 while 0 starts a transfer from the Next registers (start to the channel
 *    as soon as it is idle); writing 0 while 1 stops it after its transaction (stop); the
 *    hardware clears run when a transfer ends, but when NextConfig.repeat is 1: then a new
 *    transfer starts from the Next registers and run stays 1.
 *  - doneIE, errorIE: interrupt enables; done, error: set by each transfer's end (done) or
 *    the error input, cleared (or set) by software writing its byte.
 * The interrupts are levels: irq_done = done & doneIE, irq_err = error & errorIE. A 64-bit
 * register keeps the bits its count or address has (StrbReg of LEN_WIDTH or ADDR_WIDTH, 64 at
 * most); the bits above read 0 (the manual: WARL). wsize and rsize read LOG_BEAT (WARL: the
 * mover takes any alignment), order is kept but changes nothing (one transaction in flight:
 * always in order). ExecConfig is NextConfig as the transfer started.
 *
 *   wr, wdata, wstrb --> flags (claim, run, armed, IEs, done, error) --> start, stop, irq
 *                    --> StrbReg Next* (cleared by a claim) --> start_src, start_dst, start_len
 *   Next*, flags, ExecConfig, cur_*, left --> words
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "dark_circuit_assert.svh"

module DmaSifiveChannelRegs import DmaSifivePkg::*; #(
    parameter  ADDR_WIDTH = 32,                     // the memory's byte address, 64 at most
    parameter  LEN_WIDTH  = 32,                     // bits of a byte count, 64 at most
    parameter  LOG_BEAT   = 3                       // log2 of the mover's beat in bytes
)(
    input  wire                  clk,
    input  wire                  rst_n,             // synchronous reset, active low

    // The access
    // Words 8 to 15 (reserved, Exec*) are read only: a write there does nothing.
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire [15:0]           wr,                // word w is written now
    /* verilator lint_on UNUSEDSIGNAL */
    input  wire [31:0]           wdata,
    input  wire [3:0]            wstrb,
    output wire [15:0][31:0]     words,             // every word, read

    // The DMA channel
    output wire                  start,
    output wire [ADDR_WIDTH-1:0] start_src,
    output wire [ADDR_WIDTH-1:0] start_dst,
    output wire [LEN_WIDTH-1:0]  start_len,
    output wire                  stop,
    input  wire                  busy,
    input  wire                  done_ev,           // a transfer is complete now
    input  wire                  err_ev,            // a transfer error now
    input  wire [ADDR_WIDTH-1:0] cur_src,
    input  wire [ADDR_WIDTH-1:0] cur_dst,
    input  wire [LEN_WIDTH-1:0]  left,

    output wire                  irq_done,
    output wire                  irq_err
);
    `DC_STATIC_ASSERT(a_map, CONTROL == 0 && NEXT_CONFIG == 4 && NEXT_BYTES == 8 &&
                             NEXT_DST == 'h10 && NEXT_SRC == 'h18 && EXEC_CONFIG == 'h104 &&
                             EXEC_BYTES == 'h108 && EXEC_DST == 'h110 && EXEC_SRC == 'h118 &&
                             CLAIM_BIT == 0 && RUN_BIT == 1 && DONE_IE_BIT == 14 &&
                             ERR_IE_BIT == 15 && DONE_BIT == 30 && ERR_BIT == 31 &&
                             REPEAT_BIT == 2 && ORDER_BIT == 3 && WSIZE_LSB == 24 &&
                             RSIZE_LSB == 28)
    `DC_STATIC_ASSERT(a_widths, ADDR_WIDTH >= 8 && ADDR_WIDTH <= 64 && LEN_WIDTH >= 8 &&
                                LEN_WIDTH <= 64 && LOG_BEAT < 16)

    localparam [3:0] SIZE = 4'(LOG_BEAT);

    wire        claim, run, armed, done_ie, err_ie, done, error;    // the flags
    wire        claim_next, run_next, armed_next, done_ie_next, err_ie_next, done_next;
    wire        err_next;
    wire        wb0, wb1, wb3;      // Control's bytes 0, 1, 3 written now
    wire        claim_keep;         // claim stays: run is 1
    wire        claim_wr;           // claim as a write leaves it
    wire        claim_n, run_n, busy_n, start_n, wd_run_n;
    wire        claim_set;          // claim 0 to 1: clear the Next registers, done, error
    wire        claim_set_n;
    wire        run_set;            // run 0 to 1: a transfer from Next
    wire        run_clr;            // run 1 to 0 by software: stop
    wire        restart;            // a transfer ends with repeat: another one
    wire        repeat_n;
    wire        run_end;            // a transfer ends without repeat: run clears
    wire        run_end_n;
    wire        run_hold;
    wire        run_clr_n;
    wire        armed_keep;
    wire        armed_set;
    wire        done_acc, err_acc;  // done, error with the events of now
    wire        done_w, err_w;      // ... or the software's write
    wire [1:0]  cfg;                // NextConfig: {order, repeat}
    wire [1:0]  exec_cfg;           // ... as the transfer started
    wire        cfg_we;
    wire        cfg_strb;
    wire [1:0]  cfg_wdata;
    wire [63:0] left64, dst64, src64;   // the Exec registers as 64 bits

    // @kb: rtl/lib/block/dma/design
    // Control's bytes written now.
    And2 #(1) u_and2_wb0(.in1(wr[0]), .in2(wstrb[0]), .out(wb0));
    And2 #(1) u_and2_wb1(.in1(wr[0]), .in2(wstrb[1]), .out(wb1));
    And2 #(1) u_and2_wb3(.in1(wr[0]), .in2(wstrb[3]), .out(wb3));

    // claim: written, but not cleared while run; its rising edge clears.
    And2 #(1) u_and2_claim_keep(.in1(claim), .in2(run), .out(claim_keep));
    Or2  #(1) u_or2_claim_wr(.in1(wdata[CLAIM_BIT]), .in2(claim_keep), .out(claim_wr));
    Mux2 #(1) u_mux2_claim(.in0(claim), .in1(claim_wr), .sel(wb0), .out(claim_next));
    Inv  #(1) u_inv_claim(.in(claim), .out(claim_n));
    And3 #(1) u_and3_claim_set(.in1(wb0), .in2(wdata[CLAIM_BIT]), .in3(claim_n), .out(claim_set));
    Inv  #(1) u_inv_claim_set(.in(claim_set), .out(claim_set_n));

    // run: set by software (a start), cleared by software (a stop) or by a transfer's end
    // without repeat; with repeat the end starts another transfer.
    Inv  #(1) u_inv_run(.in(run), .out(run_n));
    Inv  #(1) u_inv_wd_run(.in(wdata[RUN_BIT]), .out(wd_run_n));
    And3 #(1) u_and3_run_set(.in1(wb0), .in2(wdata[RUN_BIT]), .in3(run_n), .out(run_set));
    And3 #(1) u_and3_run_clr(.in1(wb0), .in2(wd_run_n), .in3(run), .out(run_clr));
    Inv  #(1) u_inv_repeat(.in(cfg[0]), .out(repeat_n));
    And3 #(1) u_and3_restart(.in1(done_ev), .in2(cfg[0]), .in3(run), .out(restart));
    And2 #(1) u_and2_run_end(.in1(done_ev), .in2(repeat_n), .out(run_end));
    Inv  #(1) u_inv_run_end(.in(run_end), .out(run_end_n));
    And2 #(1) u_and2_run_hold(.in1(run), .in2(run_end_n), .out(run_hold));
    Mux2 #(1) u_mux2_run(.in0(run_hold), .in1(wdata[RUN_BIT]), .sel(wb0), .out(run_next));

    // armed: a transfer to start once the channel is idle; start and stop to the channel.
    Inv  #(1) u_inv_busy(.in(busy), .out(busy_n));
    And2 #(1) u_and2_start(.in1(armed), .in2(busy_n), .out(start));
    Inv  #(1) u_inv_start(.in(start), .out(start_n));
    Inv  #(1) u_inv_run_clr(.in(run_clr), .out(run_clr_n));
    And3 #(1) u_and3_armed_keep(.in1(armed), .in2(start_n), .in3(run_clr_n), .out(armed_keep));
    Or2  #(1) u_or2_armed_set(.in1(run_set), .in2(restart), .out(armed_set));
    Or2  #(1) u_or2_armed(.in1(armed_set), .in2(armed_keep), .out(armed_next));
    And2 #(1) u_and2_stop(.in1(run_clr), .in2(busy), .out(stop));

    // The enables, done and error.
    Mux2 #(1) u_mux2_done_ie(.in0(done_ie), .in1(wdata[DONE_IE_BIT]), .sel(wb1),
                             .out(done_ie_next));
    Mux2 #(1) u_mux2_err_ie(.in0(err_ie), .in1(wdata[ERR_IE_BIT]), .sel(wb1),
                            .out(err_ie_next));
    Or2  #(1) u_or2_done_acc(.in1(done), .in2(done_ev), .out(done_acc));
    Mux2 #(1) u_mux2_done(.in0(done_acc), .in1(wdata[DONE_BIT]), .sel(wb3), .out(done_w));
    And2 #(1) u_and2_done(.in1(done_w), .in2(claim_set_n), .out(done_next));
    Or2  #(1) u_or2_err_acc(.in1(error), .in2(err_ev), .out(err_acc));
    Mux2 #(1) u_mux2_err(.in0(err_acc), .in1(wdata[ERR_BIT]), .sel(wb3), .out(err_w));
    And2 #(1) u_and2_err(.in1(err_w), .in2(claim_set_n), .out(err_next));
    DffSyncRst #(.WIDTH(7)) u_dff_sync_rst_flags(
        .clk, .rst_n,
        .in({claim_next, run_next, armed_next, done_ie_next, err_ie_next, done_next, err_next}),
        .out({claim, run, armed, done_ie, err_ie, done, error}));
    And2 #(1) u_and2_irq_done(.in1(done), .in2(done_ie), .out(irq_done));
    And2 #(1) u_and2_irq_err(.in1(error), .in2(err_ie), .out(irq_err));

    // NextConfig {order, repeat}, cleared by a claim; ExecConfig at each start.
    Or2  #(1) u_or2_cfg_we(.in1(wr[1]), .in2(claim_set), .out(cfg_we));
    And2 #(2) u_and2_cfg_wdata(.in1(wdata[ORDER_BIT:REPEAT_BIT]), .in2({2{claim_set_n}}),
                               .out(cfg_wdata));
    Or2  #(1) u_or2_cfg_strb(.in1(wstrb[0]), .in2(claim_set), .out(cfg_strb));
    StrbReg #(.WIDTH(2)) u_strb_reg_cfg(
        .clk, .rst_n, .we(cfg_we), .wstrb(cfg_strb), .wdata(cfg_wdata), .q(cfg));
    DffEn #(2) u_dff_en_exec_cfg(.clk, .en(start), .in(cfg), .out(exec_cfg));

    // NextBytes, NextDestination, NextSource: a word pair each, cleared by a claim.
    DmaSifivePair #(.WIDTH(LEN_WIDTH)) u_pair_bytes(
        .clk, .rst_n, .wr_lo(wr[2]), .wr_hi(wr[3]), .clear(claim_set), .wdata, .wstrb,
        .q(start_len), .lo(words[2]), .hi(words[3]));
    DmaSifivePair #(.WIDTH(ADDR_WIDTH)) u_pair_dst(
        .clk, .rst_n, .wr_lo(wr[4]), .wr_hi(wr[5]), .clear(claim_set), .wdata, .wstrb,
        .q(start_dst), .lo(words[4]), .hi(words[5]));
    DmaSifivePair #(.WIDTH(ADDR_WIDTH)) u_pair_src(
        .clk, .rst_n, .wr_lo(wr[6]), .wr_hi(wr[7]), .clear(claim_set), .wdata, .wstrb,
        .q(start_src), .lo(words[6]), .hi(words[7]));

    // The words read.
    assign words[0]  = {error, done, 14'b0, err_ie, done_ie, 12'b0, run, claim};
    assign words[1]  = {SIZE, SIZE, 20'b0, cfg, 2'b00};
    assign words[8]  = '0;
    assign words[9]  = {SIZE, SIZE, 20'b0, exec_cfg, 2'b00};
    assign left64    = 64'(left);
    assign dst64     = 64'(cur_dst);
    assign src64     = 64'(cur_src);
    assign words[10] = left64[31:0];
    assign words[11] = left64[63:32];
    assign words[12] = dst64[31:0];
    assign words[13] = dst64[63:32];
    assign words[14] = src64[31:0];
    assign words[15] = src64[63:32];

endmodule

/* A 64-bit register of DmaSifive as two words (the low one first) that keeps WIDTH bits,
 * written byte by byte (StrbReg), cleared to 0 by clear; lo and hi read the two words, the
 * bits above WIDTH 0. Wiring only.
 */
module DmaSifivePair #(
    parameter  WIDTH  = 32,                         // bits kept: 8 to 64
    localparam NBYTES = (WIDTH + 7) / 8
)(
    input  wire              clk,
    input  wire              rst_n,
    input  wire              wr_lo,                 // the low word is written now
    input  wire              wr_hi,                 // ... the high word
    input  wire              clear,                 // all bytes to 0 (not with a write)
    input  wire [31:0]       wdata,
    input  wire [3:0]        wstrb,
    output wire [WIDTH-1:0]  q,
    output wire [31:0]       lo,
    output wire [31:0]       hi
);
    wire        we;
    wire        clear_n;
    wire [7:0]  strb_wr;
    wire [63:0] q64;
    // The bytes above WIDTH are not kept.
    /* verilator lint_off UNUSEDSIGNAL */
    wire [7:0]  strb;                               // the bytes of the pair written
    wire [63:0] data;
    /* verilator lint_on UNUSEDSIGNAL */

    Or3  #(1) u_or3_we(.in1(wr_lo), .in2(wr_hi), .in3(clear), .out(we));
    And2 #(8) u_and2_strb_wr(.in1({wstrb, wstrb}), .in2({{4{wr_hi}}, {4{wr_lo}}}), .out(strb_wr));
    Or2  #(8) u_or2_strb(.in1(strb_wr), .in2({8{clear}}), .out(strb));
    Inv  #(1) u_inv_clear(.in(clear), .out(clear_n));
    And2 #(64) u_and2_data(.in1({wdata, wdata}), .in2({64{clear_n}}), .out(data));
    StrbReg #(.WIDTH(WIDTH)) u_strb_reg(
        .clk, .rst_n, .we, .wstrb(strb[NBYTES-1:0]), .wdata(data[WIDTH-1:0]), .q);
    assign q64 = 64'(q);
    assign lo  = q64[31:0];
    assign hi  = q64[63:32];

endmodule

/* DMA channel: the state of one transfer, its commands to the DMA mover; made of parts and
 * gates.
 *
 * Same ports and behavior as the behave version (see there). busy, waiting, stopping and
 * done are DffSyncRst with their set and clear terms. The addresses advance by mv_n
 * (RippleCarryAdder each), the bytes left go down by it (left + ~mv_n + 1, a
 * RippleCarryAdder); a Mux2 each picks the start's value or the advanced one into a DffEn,
 * enabled at a start while idle (any, also of 0 bytes) or a done. last (the done moves the
 * bytes left) is a CmpEq, a start of 0 bytes a NorReduce.
 *
 *   start_* --Mux2--> DffEn cur_src, cur_dst, left <--Mux2-- + mv_n, - mv_n <-- mv_done
 *   left == mv_n: last --> done, idle;  stop --> stopping --> idle at the done
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "dark_circuit_assert.svh"

module DmaChannel #(
    parameter ADDR_WIDTH = 32,                      // byte address
    parameter LEN_WIDTH  = 32,                      // bits of a byte count
    parameter N_WIDTH    = 4                        // bits of mv_n (the mover's done_n)
)(
    input  wire                  clk,
    input  wire                  rst_n,             // synchronous reset, active low

    // Control
    input  wire                  start,             // begin a transfer (while idle)
    input  wire [ADDR_WIDTH-1:0] start_src,
    input  wire [ADDR_WIDTH-1:0] start_dst,
    input  wire [LEN_WIDTH-1:0]  start_len,         // bytes
    input  wire                  stop,              // end it after the transaction offered
    output wire                  busy,              // a transfer is on
    output wire                  done,              // one clock: the transfer is complete
    output wire [ADDR_WIDTH-1:0] cur_src,           // its current source
    output wire [ADDR_WIDTH-1:0] cur_dst,           // ... destination
    output wire [LEN_WIDTH-1:0]  left,              // ... bytes left

    // Mover
    output wire                  cmd_valid,         // a transaction from cur_src, cur_dst, left
    input  wire                  cmd_ready,
    input  wire                  mv_done,           // its done (this channel's)
    input  wire [N_WIDTH-1:0]    mv_n               // the bytes it moved
);
    `DC_STATIC_ASSERT(a_widths, LEN_WIDTH >= N_WIDTH && ADDR_WIDTH >= N_WIDTH)

    wire                  busy_n;
    wire                  waiting, waiting_n;
    wire                  stopping;
    wire                  take;             // the command is taken now
    wire                  len_zero;         // start_len is 0
    wire                  len_zero_n;
    wire                  idle_start;       // a start while idle
    wire                  load;             // ... of a transfer with bytes: busy
    wire                  start_empty;      // ... of 0 bytes: done at once
    wire                  last;             // left == mv_n
    wire                  adv;              // a done while busy: advance
    wire                  finish;           // ... of the last bytes
    wire                  stop_any;         // stop now or before
    wire                  end_cause;        // last or stop_any
    wire                  end_xfer;         // the done ends the transfer (last or stopped)
    wire                  end_xfer_n;
    wire                  busy_stay;
    wire                  busy_next;
    wire                  mv_done_n;
    wire                  wait_stay;
    wire                  waiting_next;
    wire                  stopping_next;
    wire                  done_next;
    wire                  update;           // load or advance the state
    wire [LEN_WIDTH-1:0]  n_len;            // mv_n, as wide as a count
    wire [ADDR_WIDTH-1:0] n_addr;           // ... as an address
    wire [LEN_WIDTH-1:0]  n_len_n;
    wire [ADDR_WIDTH-1:0] src_adv, dst_adv; // + mv_n
    wire [LEN_WIDTH-1:0]  left_adv;         // - mv_n
    wire [ADDR_WIDTH-1:0] src_next, dst_next;
    wire [LEN_WIDTH-1:0]  left_next;
    // Not needed: the carries (addresses wrap; mv_n is never more than left).
    /* verilator lint_off UNUSEDSIGNAL */
    wire                  co_src, co_dst, co_left;
    /* verilator lint_on UNUSEDSIGNAL */

    // @kb: rtl/lib/block/dma/design
    // A command while busy and not waiting.
    Inv  #(1) u_inv_waiting(.in(waiting), .out(waiting_n));
    And2 #(1) u_and2_cmd_valid(.in1(busy), .in2(waiting_n), .out(cmd_valid));
    And2 #(1) u_and2_take(.in1(cmd_valid), .in2(cmd_ready), .out(take));

    // Starts: with bytes, or of 0 bytes.
    Inv  #(1) u_inv_busy(.in(busy), .out(busy_n));
    And2 #(1) u_and2_idle_start(.in1(busy_n), .in2(start), .out(idle_start));
    NorReduce #(LEN_WIDTH) u_nor_reduce_len(.in(start_len), .out(len_zero));
    Inv  #(1) u_inv_len_zero(.in(len_zero), .out(len_zero_n));
    And2 #(1) u_and2_load(.in1(idle_start), .in2(len_zero_n), .out(load));
    And2 #(1) u_and2_start_empty(.in1(idle_start), .in2(len_zero), .out(start_empty));

    // Dones: advance; the last bytes, or a stop, end the transfer.
    assign n_len  = {{(LEN_WIDTH-N_WIDTH){1'b0}}, mv_n};
    assign n_addr = {{(ADDR_WIDTH-N_WIDTH){1'b0}}, mv_n};
    CmpEq #(LEN_WIDTH) u_cmp_eq_last(.in1(left), .in2(n_len), .eq(last));
    And2 #(1) u_and2_adv(.in1(busy), .in2(mv_done), .out(adv));
    And2 #(1) u_and2_finish(.in1(adv), .in2(last), .out(finish));
    Or2  #(1) u_or2_stop_any(.in1(stopping), .in2(stop), .out(stop_any));
    Or2  #(1) u_or2_end_cause(.in1(last), .in2(stop_any), .out(end_cause));
    And2 #(1) u_and2_end(.in1(adv), .in2(end_cause), .out(end_xfer));

    // The flags.
    Inv  #(1) u_inv_end(.in(end_xfer), .out(end_xfer_n));
    And2 #(1) u_and2_busy_stay(.in1(busy), .in2(end_xfer_n), .out(busy_stay));
    Or2  #(1) u_or2_busy(.in1(load), .in2(busy_stay), .out(busy_next));
    DffSyncRst #(.WIDTH(1)) u_dff_sync_rst_busy(.clk, .rst_n, .in(busy_next), .out(busy));
    Inv  #(1) u_inv_mv_done(.in(mv_done), .out(mv_done_n));
    And2 #(1) u_and2_wait_stay(.in1(waiting), .in2(mv_done_n), .out(wait_stay));
    Or2  #(1) u_or2_waiting(.in1(take), .in2(wait_stay), .out(waiting_next));
    DffSyncRst #(.WIDTH(1)) u_dff_sync_rst_waiting(.clk, .rst_n, .in(waiting_next),
                                                   .out(waiting));
    And3 #(1) u_and3_stopping(.in1(stop_any), .in2(busy), .in3(busy_next), .out(stopping_next));
    DffSyncRst #(.WIDTH(1)) u_dff_sync_rst_stopping(.clk, .rst_n, .in(stopping_next),
                                                    .out(stopping));
    Or2  #(1) u_or2_done(.in1(start_empty), .in2(finish), .out(done_next));
    DffSyncRst #(.WIDTH(1)) u_dff_sync_rst_done(.clk, .rst_n, .in(done_next), .out(done));

    // The state: the start's values, or advanced by mv_n.
    RippleCarryAdder #(ADDR_WIDTH) u_ripple_carry_adder_src(
        .in1(cur_src), .in2(n_addr), .ci(1'b0), .co(co_src), .sum(src_adv));
    RippleCarryAdder #(ADDR_WIDTH) u_ripple_carry_adder_dst(
        .in1(cur_dst), .in2(n_addr), .ci(1'b0), .co(co_dst), .sum(dst_adv));
    Inv  #(LEN_WIDTH) u_inv_n(.in(n_len), .out(n_len_n));
    RippleCarryAdder #(LEN_WIDTH) u_ripple_carry_adder_left(
        .in1(left), .in2(n_len_n), .ci(1'b1), .co(co_left), .sum(left_adv));
    // Every start while idle loads the state (also one of 0 bytes, as the PDMA's Exec copy).
    Mux2 #(ADDR_WIDTH) u_mux2_src(.in0(src_adv), .in1(start_src), .sel(idle_start),
                                  .out(src_next));
    Mux2 #(ADDR_WIDTH) u_mux2_dst(.in0(dst_adv), .in1(start_dst), .sel(idle_start),
                                  .out(dst_next));
    Mux2 #(LEN_WIDTH) u_mux2_left(.in0(left_adv), .in1(start_len), .sel(idle_start),
                                  .out(left_next));
    Or2  #(1) u_or2_update(.in1(idle_start), .in2(adv), .out(update));
    DffEn #(2 * ADDR_WIDTH + LEN_WIDTH) u_dff_en_state(
        .clk, .en(update), .in({src_next, dst_next, left_next}), .out({cur_src, cur_dst, left}));

    // See the behave version.
    `DC_ASSERT(a_done_waited, !mv_done || (busy && waiting))
    `DC_ASSERT(a_done_le_left, !mv_done || LEN_WIDTH'(mv_n) <= left)

endmodule

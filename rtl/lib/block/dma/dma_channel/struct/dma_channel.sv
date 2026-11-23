/* DMA channel: the state of one transfer, its commands to the DMA mover; made of parts and
 * gates.
 *
 * Same ports and behavior as the behave version (see there). busy, stopping, offered and
 * done are DffSyncRst with their set and clear terms. The issue pointer advances by the
 * offered transaction's n at a take (the larger offset: CmpGe, Mux2; the room BEAT - max =
 * ~max + 1: Inv, Incr; with MAX_BURST more than 1, when the larger offset is 0 (NorReduce)
 * the room of a burst instead, MAX_BURST - the source's beat in its block = ~beat + 1
 * beats: Inv, Incr, Mux2; n = min(left to send, room): CmpGe, Mux2), the addresses + n
 * (RippleCarryAdder each), the bytes left - n (+ ~n + 1, a RippleCarryAdder). The
 * completion counters advance by mv_n at a done the same way. A Mux2 each picks the start's
 * value or the advanced one into a DffEn, enabled at a start while idle (any, also of 0
 * bytes) or a take (the issue pointer) or a done (completion). last (the done moves the
 * bytes left) is a CmpEq, a start of 0 bytes a NorReduce, bytes left to send an OrReduce. A
 * stop ends the transfer when the counters after this clock are equal (CmpEq: nothing in
 * flight) and nothing is offered.
 *
 *   start_* --Mux2--> DffEn iss_* <--Mux2-- + n, - n <-- take          --> cmd_*
 *   start_* --Mux2--> DffEn cur_*, left <--Mux2-- + mv_n, - mv_n <-- mv_done
 *   left == mv_n: last --> done, idle;  stop --> stopping --> idle when drained
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "dark_circuit_assert.svh"

module DmaChannel #(
    parameter  ADDR_WIDTH = 32,                     // byte address
    parameter  LEN_WIDTH  = 32,                     // bits of a byte count
    parameter  N_WIDTH    = 4,                      // bits of mv_n (the mover's done_n)
    parameter  MAX_BURST  = 1,                      // beats of a burst: 1 (none), 2, 4, ...
    localparam BB         = $clog2(MAX_BURST),      // bits of a beat's number in a burst
    localparam OFF_WIDTH  = N_WIDTH - 1 - BB        // bits of a byte's offset in a beat
)(
    input  wire                  clk,
    input  wire                  rst_n,             // synchronous reset, active low

    // Control
    input  wire                  start,             // begin a transfer (while idle)
    input  wire [ADDR_WIDTH-1:0] start_src,
    input  wire [ADDR_WIDTH-1:0] start_dst,
    input  wire [LEN_WIDTH-1:0]  start_len,         // bytes
    input  wire                  stop,              // end it: no new command, drain
    output wire                  busy,              // a transfer is on
    output wire                  done,              // one clock: the transfer is complete
    output wire [ADDR_WIDTH-1:0] cur_src,           // completion: its current source
    output wire [ADDR_WIDTH-1:0] cur_dst,           // ... destination
    output wire [LEN_WIDTH-1:0]  left,              // ... bytes left

    // Mover
    output wire                  cmd_valid,         // a transaction from the issue pointer
    input  wire                  cmd_ready,
    output wire [ADDR_WIDTH-1:0] cmd_src,           // the issue pointer: the next source,
    output wire [ADDR_WIDTH-1:0] cmd_dst,           //   destination,
    output wire [N_WIDTH-1:0]    cmd_n,             //   the transaction's bytes (the mover's)
    input  wire                  mv_done,           // a done of this channel's, in order
    input  wire [N_WIDTH-1:0]    mv_n               // the bytes it moved
);
    `DC_STATIC_ASSERT(a_widths, LEN_WIDTH >= N_WIDTH && ADDR_WIDTH >= N_WIDTH &&
                                OFF_WIDTH >= 1 && (1 << BB) == MAX_BURST)

    wire [ADDR_WIDTH-1:0] iss_src, iss_dst; // the issue pointer
    wire [LEN_WIDTH-1:0]  iss_left;
    wire                  busy_n;
    wire                  stopping, stopping_n;
    wire                  offered;          // an offer of an earlier clock not taken yet
    wire                  offered_next;
    wire                  offered_next_n;
    wire                  allow;            // no stop, or an offer to keep
    wire                  to_send;          // bytes left to send
    wire                  take;             // the command is taken now
    wire                  take_n;
    wire                  len_zero;         // start_len is 0
    wire                  len_zero_n;
    wire                  idle_start;       // a start while idle
    wire                  load;             // ... of a transfer with bytes: busy
    wire                  start_empty;      // ... of 0 bytes: done at once
    wire                  last;             // left == mv_n
    wire                  adv;              // a done while busy: advance
    wire                  finish;           // ... of the last bytes
    wire                  stop_any;         // stop now or before
    wire                  drained;          // the counters after this clock are equal
    wire                  stopped;          // a stop ends the transfer now
    wire                  end_xfer;         // finished or stopped
    wire                  end_xfer_n;
    wire                  busy_stay;
    wire                  busy_next;
    wire                  stopping_next;
    wire                  done_next;
    wire                  iss_update;       // load or advance the issue pointer
    wire                  cur_update;       // load or advance the completion counters
    // The offered transaction's n.
    wire [OFF_WIDTH-1:0]  src_off, dst_off;
    wire                  src_ge;           // src_off >= dst_off
    wire [OFF_WIDTH-1:0]  off_max, off_max_n;
    wire [OFF_WIDTH:0]    room_beat;        // BEAT - off_max
    wire [N_WIDTH-1:0]    room;             // ... or a burst's, to the end of its block
    wire                  rest_ge;          // iss_left >= room
    wire [N_WIDTH-1:0]    n;                // min(iss_left, room)
    wire [LEN_WIDTH-1:0]  n_len, n_len_n;   // n as a count
    wire [ADDR_WIDTH-1:0] n_addr;           // ... as an address
    wire [ADDR_WIDTH-1:0] iss_src_adv, iss_dst_adv;     // + n
    wire [LEN_WIDTH-1:0]  iss_left_adv;     // - n
    wire [LEN_WIDTH-1:0]  iss_left_eff;     // after this clock
    wire [ADDR_WIDTH-1:0] iss_src_next, iss_dst_next;
    wire [LEN_WIDTH-1:0]  iss_left_next;
    // The completion counters.
    wire [LEN_WIDTH-1:0]  mv_len, mv_len_n; // mv_n as a count
    wire [ADDR_WIDTH-1:0] mv_addr;          // ... as an address
    wire [ADDR_WIDTH-1:0] src_adv, dst_adv; // + mv_n
    wire [LEN_WIDTH-1:0]  left_adv;         // - mv_n
    wire [LEN_WIDTH-1:0]  left_eff;         // after this clock
    wire [ADDR_WIDTH-1:0] src_next, dst_next;
    wire [LEN_WIDTH-1:0]  left_next;
    // Not needed: the carries (addresses wrap; n and mv_n are never more than left).
    /* verilator lint_off UNUSEDSIGNAL */
    wire                  co_room, co_isrc, co_idst, co_ileft, co_src, co_dst, co_left;
    /* verilator lint_on UNUSEDSIGNAL */

    // @kb: rtl/lib/block/dma/design
    // @kb: rtl/lib/block/dma/issue_pointer
    // A command while busy, bytes left to send, and no stop (or an offer to keep).
    OrReduce #(LEN_WIDTH) u_or_reduce_to_send(.in(iss_left), .out(to_send));
    Inv  #(1) u_inv_stopping(.in(stopping), .out(stopping_n));
    Or2  #(1) u_or2_allow(.in1(stopping_n), .in2(offered), .out(allow));
    And3 #(1) u_and3_cmd_valid(.in1(busy), .in2(to_send), .in3(allow), .out(cmd_valid));
    And2 #(1) u_and2_take(.in1(cmd_valid), .in2(cmd_ready), .out(take));
    Inv  #(1) u_inv_take(.in(take), .out(take_n));
    And2 #(1) u_and2_offered(.in1(cmd_valid), .in2(take_n), .out(offered_next));
    DffSyncRst #(.WIDTH(1)) u_dff_sync_rst_offered(.clk, .rst_n, .in(offered_next),
                                                   .out(offered));
    assign cmd_src  = iss_src;
    assign cmd_dst  = iss_dst;
    assign cmd_n    = n;

    // The offered transaction's n.
    assign src_off = iss_src[OFF_WIDTH-1:0];
    assign dst_off = iss_dst[OFF_WIDTH-1:0];
    CmpGe #(OFF_WIDTH) u_cmp_ge_off(.in1(src_off), .in2(dst_off), .ge(src_ge));
    Mux2 #(OFF_WIDTH) u_mux2_off_max(.in0(dst_off), .in1(src_off), .sel(src_ge), .out(off_max));
    Inv  #(OFF_WIDTH) u_inv_off_max(.in(off_max), .out(off_max_n));
    Incr #(.WIDTH(OFF_WIDTH)) u_incr_room(.in(off_max_n), .out(room_beat[OFF_WIDTH-1:0]),
                                          .co(co_room));
    assign room_beat[OFF_WIDTH] = co_room;
    // @kb: rtl/lib/block/dma/read_bursts
    if (BB > 0) begin: g_burst
        wire [BB-1:0] sb, sb_n;     // the source's beat in its block
        wire [BB-1:0] rb;           // MAX_BURST - sb beats, with co_rb on top
        wire          co_rb;
        wire          off_zero;     // both offsets 0: a burst
        assign sb = iss_src[OFF_WIDTH +: BB];
        Inv  #(BB) u_inv_sb(.in(sb), .out(sb_n));
        Incr #(.WIDTH(BB)) u_incr_burst(.in(sb_n), .out(rb), .co(co_rb));
        NorReduce #(OFF_WIDTH) u_nor_reduce_off(.in(off_max), .out(off_zero));
        Mux2 #(N_WIDTH) u_mux2_room(.in0({{BB{1'b0}}, room_beat}),
                                    .in1({co_rb, rb, {OFF_WIDTH{1'b0}}}), .sel(off_zero),
                                    .out(room));
    end else begin: g_single
        assign room = room_beat;
    end
    CmpGe #(LEN_WIDTH) u_cmp_ge_rest(.in1(iss_left),
                                     .in2({{(LEN_WIDTH-N_WIDTH){1'b0}}, room}), .ge(rest_ge));
    Mux2 #(N_WIDTH) u_mux2_n(.in0(iss_left[N_WIDTH-1:0]), .in1(room), .sel(rest_ge), .out(n));

    // Starts: with bytes, or of 0 bytes.
    Inv  #(1) u_inv_busy(.in(busy), .out(busy_n));
    And2 #(1) u_and2_idle_start(.in1(busy_n), .in2(start), .out(idle_start));
    NorReduce #(LEN_WIDTH) u_nor_reduce_len(.in(start_len), .out(len_zero));
    Inv  #(1) u_inv_len_zero(.in(len_zero), .out(len_zero_n));
    And2 #(1) u_and2_load(.in1(idle_start), .in2(len_zero_n), .out(load));
    And2 #(1) u_and2_start_empty(.in1(idle_start), .in2(len_zero), .out(start_empty));

    // The issue pointer: the start's values, or advanced by n at a take.
    assign n_len  = {{(LEN_WIDTH-N_WIDTH){1'b0}}, n};
    assign n_addr = {{(ADDR_WIDTH-N_WIDTH){1'b0}}, n};
    RippleCarryAdder #(ADDR_WIDTH) u_ripple_carry_adder_isrc(
        .in1(iss_src), .in2(n_addr), .ci(1'b0), .co(co_isrc), .sum(iss_src_adv));
    RippleCarryAdder #(ADDR_WIDTH) u_ripple_carry_adder_idst(
        .in1(iss_dst), .in2(n_addr), .ci(1'b0), .co(co_idst), .sum(iss_dst_adv));
    Inv  #(LEN_WIDTH) u_inv_n(.in(n_len), .out(n_len_n));
    RippleCarryAdder #(LEN_WIDTH) u_ripple_carry_adder_ileft(
        .in1(iss_left), .in2(n_len_n), .ci(1'b1), .co(co_ileft), .sum(iss_left_adv));
    Mux2 #(LEN_WIDTH) u_mux2_ileft_eff(.in0(iss_left), .in1(iss_left_adv), .sel(take),
                                       .out(iss_left_eff));
    Mux2 #(ADDR_WIDTH) u_mux2_isrc(.in0(iss_src_adv), .in1(start_src), .sel(idle_start),
                                   .out(iss_src_next));
    Mux2 #(ADDR_WIDTH) u_mux2_idst(.in0(iss_dst_adv), .in1(start_dst), .sel(idle_start),
                                   .out(iss_dst_next));
    Mux2 #(LEN_WIDTH) u_mux2_ileft(.in0(iss_left_adv), .in1(start_len), .sel(idle_start),
                                   .out(iss_left_next));
    Or2  #(1) u_or2_iss_update(.in1(idle_start), .in2(take), .out(iss_update));
    DffEn #(2 * ADDR_WIDTH + LEN_WIDTH) u_dff_en_issue(
        .clk, .en(iss_update), .in({iss_src_next, iss_dst_next, iss_left_next}),
        .out({iss_src, iss_dst, iss_left}));

    // The completion counters: the start's values, or advanced by mv_n at a done.
    assign mv_len  = {{(LEN_WIDTH-N_WIDTH){1'b0}}, mv_n};
    assign mv_addr = {{(ADDR_WIDTH-N_WIDTH){1'b0}}, mv_n};
    CmpEq #(LEN_WIDTH) u_cmp_eq_last(.in1(left), .in2(mv_len), .eq(last));
    And2 #(1) u_and2_adv(.in1(busy), .in2(mv_done), .out(adv));
    RippleCarryAdder #(ADDR_WIDTH) u_ripple_carry_adder_src(
        .in1(cur_src), .in2(mv_addr), .ci(1'b0), .co(co_src), .sum(src_adv));
    RippleCarryAdder #(ADDR_WIDTH) u_ripple_carry_adder_dst(
        .in1(cur_dst), .in2(mv_addr), .ci(1'b0), .co(co_dst), .sum(dst_adv));
    Inv  #(LEN_WIDTH) u_inv_mv_n(.in(mv_len), .out(mv_len_n));
    RippleCarryAdder #(LEN_WIDTH) u_ripple_carry_adder_left(
        .in1(left), .in2(mv_len_n), .ci(1'b1), .co(co_left), .sum(left_adv));
    Mux2 #(LEN_WIDTH) u_mux2_left_eff(.in0(left), .in1(left_adv), .sel(mv_done),
                                      .out(left_eff));
    // Every start while idle loads the state (also one of 0 bytes, as the PDMA's Exec copy).
    Mux2 #(ADDR_WIDTH) u_mux2_src(.in0(src_adv), .in1(start_src), .sel(idle_start),
                                  .out(src_next));
    Mux2 #(ADDR_WIDTH) u_mux2_dst(.in0(dst_adv), .in1(start_dst), .sel(idle_start),
                                  .out(dst_next));
    Mux2 #(LEN_WIDTH) u_mux2_left(.in0(left_adv), .in1(start_len), .sel(idle_start),
                                  .out(left_next));
    Or2  #(1) u_or2_cur_update(.in1(idle_start), .in2(adv), .out(cur_update));
    DffEn #(2 * ADDR_WIDTH + LEN_WIDTH) u_dff_en_state(
        .clk, .en(cur_update), .in({src_next, dst_next, left_next}),
        .out({cur_src, cur_dst, left}));

    // The end: the last bytes done, or a stop drained (nothing in flight, nothing offered).
    And2 #(1) u_and2_finish(.in1(adv), .in2(last), .out(finish));
    Or2  #(1) u_or2_stop_any(.in1(stopping), .in2(stop), .out(stop_any));
    CmpEq #(LEN_WIDTH) u_cmp_eq_drained(.in1(left_eff), .in2(iss_left_eff), .eq(drained));
    Inv  #(1) u_inv_offered_next(.in(offered_next), .out(offered_next_n));
    And3 #(1) u_and3_stopped(.in1(stop_any), .in2(drained), .in3(offered_next_n), .out(stopped));
    Or2  #(1) u_or2_end(.in1(finish), .in2(stopped), .out(end_xfer));

    // The flags.
    Inv  #(1) u_inv_end(.in(end_xfer), .out(end_xfer_n));
    And2 #(1) u_and2_busy_stay(.in1(busy), .in2(end_xfer_n), .out(busy_stay));
    Or2  #(1) u_or2_busy(.in1(load), .in2(busy_stay), .out(busy_next));
    DffSyncRst #(.WIDTH(1)) u_dff_sync_rst_busy(.clk, .rst_n, .in(busy_next), .out(busy));
    And3 #(1) u_and3_stopping(.in1(stop_any), .in2(busy), .in3(busy_next), .out(stopping_next));
    DffSyncRst #(.WIDTH(1)) u_dff_sync_rst_stopping(.clk, .rst_n, .in(stopping_next),
                                                    .out(stopping));
    Or2  #(1) u_or2_done(.in1(start_empty), .in2(finish), .out(done_next));
    DffSyncRst #(.WIDTH(1)) u_dff_sync_rst_done(.clk, .rst_n, .in(done_next), .out(done));

    // See the behave version.
    `DC_ASSERT(a_done_in_flight, !mv_done || (busy && left != iss_left))
    `DC_ASSERT(a_done_le_left, !mv_done || LEN_WIDTH'(mv_n) <= left - iss_left)

endmodule

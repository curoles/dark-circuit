/* Request multiplexer: N_REQ request channels to one target, round-robin or by fixed
 * priority, the answers back to their requesters in order; made of blocks and gates.
 *
 * Same ports and behavior as the behave version (see there). A RoundRobinArbiter picks the
 * winner (advanced when the target takes it); while an offer waits the arbiter sees only the
 * grant of the clock before (a DffEn keeps it, a DffSyncRst says it waits). With FIXED_PRIO=1
 * gates pick instead: requester i wins when it asks and no lower one does (an OrReduce of
 * the requests below it, Inv, And2). MuxOneHot takes
 * the winner's fields; a Fifo of 1 << PENDING_WIDTH one-hot requester numbers, each with its
 * req_len (MuxOneHot of the winner's), keeps the owners of the answers waiting, the oldest's
 * bit goes with the target's answers; a beat count (DffSyncRst, Incr, Mux2) against the
 * oldest's req_len (CmpEq) pops it at its last answer. A request with req_rsp waits while
 * the Fifo is full. PENDING_WIDTH counts requests (each with all its answers), where
 * ReqDemux's counts answers.
 *
 *   req_valid --Mux2 (lock: grant_q)--> RoundRobinArbiter --> grant --MuxOneHot--> target
 *   taken with req_rsp: grant --> Fifo --oldest--> And2 tgt_rsp_valid --> rsp_valid
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "dark_circuit_assert.svh"

module ReqMux #(
    parameter N_REQ         = 2,        // requesters, 1 or more
    parameter REQ_WIDTH     = 32,       // bits of a request's fields but we and rsp
    parameter RSP_WIDTH     = 32,       // bits of an answer
    parameter PENDING_WIDTH = 1,        // up to 1 << PENDING_WIDTH answers wait
    parameter FIXED_PRIO    = 0,        // 0 round-robin; 1 requester 0 first, then 1, ...
    parameter LEN_WIDTH     = 1         // bits of req_len: a burst of up to 1 << it answers
)(
    input  wire                            clk,
    input  wire                            rst_n,           // synchronous, active low
    // Requesters
    input  wire [N_REQ-1:0]                req_valid,
    output wire [N_REQ-1:0]                req_ready,
    input  wire [N_REQ-1:0]                req_we,          // a write
    input  wire [N_REQ-1:0]                req_rsp,         // wants an answer
    input  wire [N_REQ-1:0][LEN_WIDTH-1:0] req_len,         // answers - 1 (with req_rsp)
    input  wire [N_REQ-1:0][REQ_WIDTH-1:0] req_fields,
    output wire [N_REQ-1:0]                rsp_valid,       // an answer to requester r
    output wire [RSP_WIDTH-1:0]            rsp_data,        // ... to every requester
    // Target
    output wire                            tgt_req_valid,
    input  wire                            tgt_req_ready,
    output wire                            tgt_req_we,
    output wire                            tgt_req_rsp,
    output wire [REQ_WIDTH-1:0]            tgt_req_fields,
    input  wire                            tgt_rsp_valid,
    input  wire [RSP_WIDTH-1:0]            tgt_rsp_data
);
    `DC_STATIC_ASSERT(a_sizes, N_REQ >= 1 && PENDING_WIDTH >= 1)
    `DC_STATIC_ASSERT(a_fixed_prio, FIXED_PRIO == 0 || FIXED_PRIO == 1)
    `DC_STATIC_ASSERT(a_len_width, LEN_WIDTH >= 1)

    localparam N = N_REQ;

    wire [N-1:0] arb_req;           // what the arbiter sees
    wire [N-1:0] grant;             // one-hot: the winner now
    wire [N-1:0] grant_q;           // the grant of the clock before
    wire         lock;              // an offer waits: keep its grant
    wire         lock_next;
    wire         any;               // a winner
    wire [N-1:0] win_asks;
    wire         win_ask;           // the winner's request wants an answer
    wire [N-1:0] win_writes;
    wire         full;              // answers waiting: no more
    wire         blocked;           // a request with req_rsp while full
    wire         blocked_n;
    wire         tgt_take;          // the target takes the winner's request now
    wire         tgt_take_n;
    wire         ask_taken;
    wire [N-1:0] oldest;            // the requester of the oldest answer waiting
    wire [LEN_WIDTH-1:0] win_len;   // the winner's req_len
    wire [LEN_WIDTH-1:0] old_len;   // the oldest's
    wire [LEN_WIDTH-1:0] beat;      // its answers so far
    wire [LEN_WIDTH-1:0] beat_inc;
    wire [LEN_WIDTH-1:0] beat_step; // beat + 1, or 0 after the last
    wire [LEN_WIDTH-1:0] beat_next;
    wire         last;              // the answer now is the oldest's last
    wire         pop;               // ... so it leaves the Fifo
    // Not needed: the beat count's carry (it wraps to 0 at the last anyway).
    /* verilator lint_off UNUSEDSIGNAL */
    wire         co_beat;
    /* verilator lint_on UNUSEDSIGNAL */
    // Not needed: the Fifo's count and thresholds; empty is checked by an assertion.
    /* verilator lint_off UNUSEDSIGNAL */
    wire         empty;
    wire [PENDING_WIDTH:0] count;
    wire         almost_full, almost_empty;
    /* verilator lint_on UNUSEDSIGNAL */

    // @kb: rtl/lib/block/req_mux/design
    // The winner; kept while its offer waits.
    Mux2 #(N) u_mux2_arb_req(.in0(req_valid), .in1(grant_q), .sel(lock), .out(arb_req));
    // @kb: rtl/lib/block/req_mux/fixed_priority
    if (N > 1 && FIXED_PRIO != 0) begin: g_fixed
        assign grant[0] = arb_req[0];
        for (genvar i = 1; i < N; i++) begin: g_req
            wire below;             // a lower requester asks
            wire below_n;
            OrReduce #(i) u_or_reduce_below(.in(arb_req[i-1:0]), .out(below));
            Inv  #(1) u_inv_below(.in(below), .out(below_n));
            And2 #(1) u_and2_grant(.in1(arb_req[i]), .in2(below_n), .out(grant[i]));
        end
    end else if (N > 1) begin: g_arbiter
        RoundRobinArbiter #(.N(N)) u_arbiter(
            .clk, .rst_n, .req(arb_req), .advance(tgt_take), .grant);
    end else begin: g_one
        assign grant = arb_req;
    end
    DffEn #(N) u_dff_en_grant(.clk, .en(1'b1), .in(grant), .out(grant_q));
    OrReduce #(N) u_or_reduce_any(.in(grant), .out(any));
    Inv  #(1) u_inv_take(.in(tgt_take), .out(tgt_take_n));
    And2 #(1) u_and2_lock(.in1(any), .in2(tgt_take_n), .out(lock_next));
    DffSyncRst #(.WIDTH(1)) u_dff_sync_rst_lock(.clk, .rst_n, .in(lock_next), .out(lock));

    // The request to the target: the winner's, unless it wants an answer while full.
    And2 #(N) u_and2_win_asks(.in1(grant), .in2(req_rsp), .out(win_asks));
    OrReduce #(N) u_or_reduce_win_ask(.in(win_asks), .out(win_ask));
    assign tgt_req_rsp = win_ask;
    And2 #(1) u_and2_blocked(.in1(full), .in2(win_ask), .out(blocked));
    Inv  #(1) u_inv_blocked(.in(blocked), .out(blocked_n));
    And2 #(1) u_and2_tgt_valid(.in1(any), .in2(blocked_n), .out(tgt_req_valid));
    And2 #(N) u_and2_win_writes(.in1(grant), .in2(req_we), .out(win_writes));
    OrReduce #(N) u_or_reduce_we(.in(win_writes), .out(tgt_req_we));
    MuxOneHot #(.N(N), .WIDTH(REQ_WIDTH)) u_mux_one_hot_fields(
        .in(req_fields), .sel(grant), .out(tgt_req_fields));
    And2 #(1) u_and2_take(.in1(tgt_req_valid), .in2(tgt_req_ready), .out(tgt_take));
    And2 #(N) u_and2_ready(.in1(grant), .in2({N{tgt_take}}), .out(req_ready));
    And2 #(1) u_and2_ask_taken(.in1(tgt_take), .in2(win_ask), .out(ask_taken));

    // The owners of the answers waiting, each with its req_len; the answers to the oldest,
    // which leaves with its last.
    // @kb: rtl/lib/block/bursts
    MuxOneHot #(.N(N), .WIDTH(LEN_WIDTH)) u_mux_one_hot_len(
        .in(req_len), .sel(grant), .out(win_len));
    Fifo #(.ADDR_WIDTH(PENDING_WIDTH), .DATA_WIDTH(N + LEN_WIDTH)) u_fifo_owner(
        .clk, .rst_n, .write(ask_taken), .data_in({grant, win_len}), .read(pop),
        .data_out({oldest, old_len}), .empty, .full, .count, .almost_full, .almost_empty);
    CmpEq #(LEN_WIDTH) u_cmp_eq_last(.in1(beat), .in2(old_len), .eq(last));
    And2 #(1) u_and2_pop(.in1(tgt_rsp_valid), .in2(last), .out(pop));
    Incr #(.WIDTH(LEN_WIDTH)) u_incr_beat(.in(beat), .out(beat_inc), .co(co_beat));
    Mux2 #(LEN_WIDTH) u_mux2_beat_step(.in0(beat_inc), .in1('0), .sel(last), .out(beat_step));
    Mux2 #(LEN_WIDTH) u_mux2_beat(.in0(beat), .in1(beat_step), .sel(tgt_rsp_valid),
                                  .out(beat_next));
    DffSyncRst #(.WIDTH(LEN_WIDTH)) u_dff_sync_rst_beat(.clk, .rst_n, .in(beat_next),
                                                        .out(beat));
    And2 #(N) u_and2_rsp(.in1(oldest), .in2({N{tgt_rsp_valid}}), .out(rsp_valid));
    assign rsp_data = tgt_rsp_data;

    // See the behave version.
    `DC_ASSERT(a_one_grant, $onehot0(grant))
    `DC_ASSERT_NEXT(a_grant_held, tgt_req_valid && !tgt_req_ready, $stable(grant))
    `DC_ASSERT(a_answer_expected, !tgt_rsp_valid || !empty)

endmodule

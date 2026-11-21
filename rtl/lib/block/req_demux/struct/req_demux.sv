/* Request demultiplexer: one request channel to one of N_TARGETS targets by a one-hot
 * select, the answers back in order; made of blocks and gates.
 *
 * Same ports, parameters and behavior as the behave version (see there): PENDING_WIDTH
 * counts answers (a burst's beats), where ReqMux's counts requests.
 *   other         = OrReduce(req_sel AND ~owner)        busy = OrReduce(pending)
 *   need          = pending + req_len + 1 (RippleCarryAdder, carry in 1)
 *   blocked       = (busy AND other) OR (CmpGe(need, MAX + 1) AND req_rsp)
 *   req_ready     = ~blocked AND OrReduce(tgt_req_ready AND req_sel)
 *   tgt_req_valid = req_sel AND (req_valid AND ~blocked)
 *   pending       = DffSyncRst of pending + (req_len AND ask_taken) + ask_taken - rsp_valid
 *                   (two RippleCarryAdders: the second adds rsp_valid's all-ones, -1)
 *   owner         = DffEn(req_sel) on a request taken with req_rsp
 *   rsp_valid     = OrReduce(tgt_rsp_valid AND owner)    rsp_data = MuxOneHot by owner
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "dark_circuit_assert.svh"

module ReqDemux #(
    parameter N_TARGETS     = 2,        // targets
    parameter RSP_WIDTH     = 32,       // bits of an answer
    parameter PENDING_WIDTH = 1,        // up to 1 << PENDING_WIDTH answers wait
    parameter LEN_WIDTH     = 1         // bits of req_len: a burst of up to 1 << it answers
)(
    input  wire                                clk,
    input  wire                                rst_n,           // synchronous, active low
    // Initiator side
    input  wire                                req_valid,
    output wire                                req_ready,
    input  wire                                req_rsp,         // wants an answer
    input  wire [LEN_WIDTH-1:0]                req_len,         // answers - 1 (with req_rsp)
    input  wire [N_TARGETS-1:0]                req_sel,         // one-hot: the target
    output wire                                rsp_valid,       // an answer
    output wire [RSP_WIDTH-1:0]                rsp_data,
    // Targets
    output wire [N_TARGETS-1:0]                tgt_req_valid,
    input  wire [N_TARGETS-1:0]                tgt_req_ready,
    input  wire [N_TARGETS-1:0]                tgt_rsp_valid,
    input  wire [N_TARGETS-1:0][RSP_WIDTH-1:0] tgt_rsp_data
);
    `DC_STATIC_ASSERT(a_sizes, N_TARGETS >= 1 && PENDING_WIDTH >= 1 && LEN_WIDTH >= 1)

    localparam [PENDING_WIDTH:0] MAX = 1 << PENDING_WIDTH;
    localparam PW = PENDING_WIDTH + 1;      // bits of pending
    // Bits of pending + req_len + 1.
    localparam SW = ((PW > LEN_WIDTH) ? PW : LEN_WIDTH) + 1;

    wire [PENDING_WIDTH:0] pending;     // answers that requests taken still wait for
    wire [SW-1:0]          need;        // ... with all of this request's
    wire [PW-1:0]          len_taken;   // req_len of a request taken with req_rsp, else 0
    wire [PW-1:0]          pend_up;     // pending + len_taken + ask_taken
    wire [PW-1:0]          pend_next;   // ... - rsp_valid
    wire [N_TARGETS-1:0]   owner;       // their target (meaningful while pending)
    wire [N_TARGETS-1:0]   owner_n;
    wire [N_TARGETS-1:0]   sel_other;   // req_sel AND ~owner
    wire [N_TARGETS-1:0]   sel_ready;   // req_sel AND tgt_req_ready
    wire [N_TARGETS-1:0]   rsp_owner;   // tgt_rsp_valid AND owner
    wire                   busy;        // answers wait
    wire                   other;       // the request is for another target than owner
    wire                   full;        // this request's answers do not all fit
    wire                   busy_other;
    wire                   full_ask;
    wire                   blocked;     // the request waits
    wire                   blocked_n;
    wire                   any_ready;   // the selected target is ready
    wire                   go;          // the request goes to its target
    wire                   ask_taken;   // a request that wants an answer is taken now
    // Not needed: the sums' carries (pending never passes MAX or goes below 0).
    /* verilator lint_off UNUSEDSIGNAL */
    wire                   co_need, co_up, co_next;
    /* verilator lint_on UNUSEDSIGNAL */

    // The answers of one target at a time: a request to another waits for them.
    // @kb: rtl/lib/block/req_demux/design
    Inv      #(N_TARGETS) u_inv_owner    (.in(owner), .out(owner_n));
    And2     #(N_TARGETS) u_and2_other   (.in1(req_sel), .in2(owner_n), .out(sel_other));
    OrReduce #(N_TARGETS) u_or_reduce_other(.in(sel_other), .out(other));
    OrReduce #(PENDING_WIDTH + 1) u_or_reduce_busy(.in(pending), .out(busy));
    // @kb: rtl/lib/block/bursts
    RippleCarryAdder #(SW) u_ripple_carry_adder_need(
        .in1(SW'(pending)), .in2(SW'(req_len)), .ci(1'b1), .co(co_need), .sum(need));
    CmpGe    #(SW) u_cmp_ge_full(.in1(need), .in2(SW'(MAX) + SW'(1)), .ge(full));
    And2     #(1) u_and2_busy     (.in1(busy), .in2(other), .out(busy_other));
    And2     #(1) u_and2_full     (.in1(full), .in2(req_rsp), .out(full_ask));
    Or2      #(1) u_or2_blocked   (.in1(busy_other), .in2(full_ask), .out(blocked));
    Inv      #(1) u_inv_blocked   (.in(blocked), .out(blocked_n));

    And2     #(N_TARGETS) u_and2_ready(.in1(req_sel), .in2(tgt_req_ready), .out(sel_ready));
    OrReduce #(N_TARGETS) u_or_reduce_ready(.in(sel_ready), .out(any_ready));
    And2     #(1) u_and2_req_ready(.in1(blocked_n), .in2(any_ready), .out(req_ready));
    And2     #(1) u_and2_go       (.in1(req_valid), .in2(blocked_n), .out(go));
    And2     #(N_TARGETS) u_and2_tgt_valid(.in1(req_sel), .in2({N_TARGETS{go}}),
                                           .out(tgt_req_valid));
    And3     #(1) u_and3_ask_taken(.in1(req_valid), .in2(req_ready), .in3(req_rsp),
                                   .out(ask_taken));

    // Answers waiting: up by req_len + 1 on a request taken that wants them, down by one on
    // an answer.
    And2     #(PW) u_and2_len_taken(.in1(PW'(req_len)), .in2({PW{ask_taken}}), .out(len_taken));
    RippleCarryAdder #(PW) u_ripple_carry_adder_up(
        .in1(pending), .in2(len_taken), .ci(ask_taken), .co(co_up), .sum(pend_up));
    RippleCarryAdder #(PW) u_ripple_carry_adder_next(
        .in1(pend_up), .in2({PW{rsp_valid}}), .ci(1'b0), .co(co_next), .sum(pend_next));
    DffSyncRst #(.WIDTH(PW)) u_dff_sync_rst_pending(.clk, .rst_n, .in(pend_next), .out(pending));
    DffEn    #(N_TARGETS) u_dff_en_owner(.clk, .en(ask_taken), .in(req_sel), .out(owner));

    // The owner's answer.
    And2     #(N_TARGETS) u_and2_rsp  (.in1(tgt_rsp_valid), .in2(owner), .out(rsp_owner));
    OrReduce #(N_TARGETS) u_or_reduce_rsp(.in(rsp_owner), .out(rsp_valid));
    MuxOneHot #(.N(N_TARGETS), .WIDTH(RSP_WIDTH)) u_mux_one_hot_rsp(
        .in(tgt_rsp_data), .sel(owner), .out(rsp_data));

    // See the behave version.
    `DC_ASSERT(a_one_target, !req_valid || $onehot(req_sel))
    `DC_ASSERT(a_len_fits, !(req_valid && req_rsp && SW'(req_len) + SW'(1) > SW'(MAX)))
    `DC_ASSERT(a_answer_expected, tgt_rsp_valid == '0 || (busy && $onehot(tgt_rsp_valid) &&
                                                          (tgt_rsp_valid & ~owner) == '0))

endmodule

/* Request demultiplexer: one request channel to one of N_TARGETS targets by a one-hot
 * select, the answers back in order; made of blocks and gates.
 *
 * Same ports, parameters and behavior as the behave version (see there).
 *   other         = OrReduce(req_sel AND ~owner)        busy = OrReduce(pending)
 *   blocked       = (busy AND other) OR (CmpEq(pending, MAX) AND ~req_we)
 *   req_ready     = ~blocked AND OrReduce(tgt_req_ready AND req_sel)
 *   tgt_req_valid = req_sel AND (req_valid AND ~blocked)
 *   pending       = Counter: up on a read taken, down on an answer, held on both or none
 *   owner         = DffEn(req_sel) on a read taken
 *   rsp_valid     = OrReduce(tgt_rsp_valid AND owner)    rsp_data = MuxOneHot by owner
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "dark_circuit_assert.svh"

module ReqDemux #(
    parameter N_TARGETS     = 2,        // targets
    parameter RSP_WIDTH     = 32,       // bits of an answer
    parameter PENDING_WIDTH = 1         // up to 1 << PENDING_WIDTH reads wait for answers
)(
    input  wire                                clk,
    input  wire                                rst_n,           // synchronous, active low
    // Initiator side
    input  wire                                req_valid,
    output wire                                req_ready,
    input  wire                                req_we,          // a write: no answer
    input  wire [N_TARGETS-1:0]                req_sel,         // one-hot: the target
    output wire                                rsp_valid,       // the answer to a read
    output wire [RSP_WIDTH-1:0]                rsp_data,
    // Targets
    output wire [N_TARGETS-1:0]                tgt_req_valid,
    input  wire [N_TARGETS-1:0]                tgt_req_ready,
    input  wire [N_TARGETS-1:0]                tgt_rsp_valid,
    input  wire [N_TARGETS-1:0][RSP_WIDTH-1:0] tgt_rsp_data
);
    `DC_STATIC_ASSERT(a_sizes, N_TARGETS >= 1 && PENDING_WIDTH >= 1)

    localparam [PENDING_WIDTH:0] MAX = 1 << PENDING_WIDTH;

    wire [PENDING_WIDTH:0] pending;     // reads taken and not answered
    wire [N_TARGETS-1:0]   owner;       // their target (meaningful while pending)
    wire [N_TARGETS-1:0]   owner_n;
    wire [N_TARGETS-1:0]   sel_other;   // req_sel AND ~owner
    wire [N_TARGETS-1:0]   sel_ready;   // req_sel AND tgt_req_ready
    wire [N_TARGETS-1:0]   rsp_owner;   // tgt_rsp_valid AND owner
    wire                   busy;        // reads wait for answers
    wire                   other;       // the request is for another target than owner
    wire                   full;        // 1 << PENDING_WIDTH reads wait
    wire                   we_n;
    wire                   busy_other;
    wire                   full_read;
    wire                   blocked;     // the request waits
    wire                   blocked_n;
    wire                   any_ready;   // the selected target is ready
    wire                   go;          // the request goes to its target
    wire                   read_taken;  // a read is taken now
    wire                   count_en;
    // Not needed: the counter never passes MAX or goes below 0.
    /* verilator lint_off UNUSEDSIGNAL */
    wire                   count_co;
    /* verilator lint_on UNUSEDSIGNAL */

    // The answers of one target at a time: a request to another waits for them.
    // @kb: rtl/lib/block/req_demux/design
    Inv      #(N_TARGETS) u_inv_owner    (.in(owner), .out(owner_n));
    And2     #(N_TARGETS) u_and2_other   (.in1(req_sel), .in2(owner_n), .out(sel_other));
    OrReduce #(N_TARGETS) u_or_reduce_other(.in(sel_other), .out(other));
    OrReduce #(PENDING_WIDTH + 1) u_or_reduce_busy(.in(pending), .out(busy));
    CmpEq    #(PENDING_WIDTH + 1) u_cmp_eq_full(.in1(pending), .in2(MAX), .eq(full));
    Inv      #(1) u_inv_we        (.in(req_we), .out(we_n));
    And2     #(1) u_and2_busy     (.in1(busy), .in2(other), .out(busy_other));
    And2     #(1) u_and2_full     (.in1(full), .in2(we_n), .out(full_read));
    Or2      #(1) u_or2_blocked   (.in1(busy_other), .in2(full_read), .out(blocked));
    Inv      #(1) u_inv_blocked   (.in(blocked), .out(blocked_n));

    And2     #(N_TARGETS) u_and2_ready(.in1(req_sel), .in2(tgt_req_ready), .out(sel_ready));
    OrReduce #(N_TARGETS) u_or_reduce_ready(.in(sel_ready), .out(any_ready));
    And2     #(1) u_and2_req_ready(.in1(blocked_n), .in2(any_ready), .out(req_ready));
    And2     #(1) u_and2_go       (.in1(req_valid), .in2(blocked_n), .out(go));
    And2     #(N_TARGETS) u_and2_tgt_valid(.in1(req_sel), .in2({N_TARGETS{go}}),
                                           .out(tgt_req_valid));
    And3     #(1) u_and3_read_taken(.in1(req_valid), .in2(req_ready), .in3(we_n),
                                    .out(read_taken));

    // Reads waiting: up on a read taken, down on an answer.
    Xor2     #(1) u_xor2_count_en (.in1(read_taken), .in2(rsp_valid), .out(count_en));
    Counter  #(.WIDTH(PENDING_WIDTH + 1)) u_counter_pending(
        .clk, .rst_n, .load(1'b0), .in({(PENDING_WIDTH + 1){1'b0}}), .up_down(read_taken),
        .count_en, .out(pending), .co(count_co));
    DffEn    #(N_TARGETS) u_dff_en_owner(.clk, .en(read_taken), .in(req_sel), .out(owner));

    // The owner's answer.
    And2     #(N_TARGETS) u_and2_rsp  (.in1(tgt_rsp_valid), .in2(owner), .out(rsp_owner));
    OrReduce #(N_TARGETS) u_or_reduce_rsp(.in(rsp_owner), .out(rsp_valid));
    MuxOneHot #(.N(N_TARGETS), .WIDTH(RSP_WIDTH)) u_mux_one_hot_rsp(
        .in(tgt_rsp_data), .sel(owner), .out(rsp_data));

    // A request names one target; answers come only from the owner, while reads wait.
    `DC_ASSERT(a_one_target, !req_valid || $onehot(req_sel))
    `DC_ASSERT(a_answer_expected, tgt_rsp_valid == '0 || (busy && $onehot(tgt_rsp_valid) &&
                                                          (tgt_rsp_valid & ~owner) == '0))

endmodule

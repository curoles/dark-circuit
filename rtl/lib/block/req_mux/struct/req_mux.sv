/* Request multiplexer: N_REQ request channels to one target, round-robin, the answers back to
 * their requesters in order; made of blocks and gates.
 *
 * Same ports and behavior as the behave version (see there). A RoundRobinArbiter picks the
 * winner (advanced when the target takes it); while an offer waits the arbiter sees only the
 * grant of the clock before (a DffEn keeps it, a DffSyncRst says it waits). MuxOneHot takes
 * the winner's fields; a Fifo of 1 << PENDING_WIDTH one-hot requester numbers keeps the
 * owners of the reads waiting, the oldest's bit goes with the target's answer. A read waits
 * while the Fifo is full.
 *
 *   req_valid --Mux2 (lock: grant_q)--> RoundRobinArbiter --> grant --MuxOneHot--> target
 *   read taken: grant --> Fifo --oldest--> And2 tgt_rsp_valid --> rsp_valid
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "dark_circuit_assert.svh"

module ReqMux #(
    parameter N_REQ         = 2,        // requesters, 1 or more
    parameter REQ_WIDTH     = 32,       // bits of a request's fields but we
    parameter RSP_WIDTH     = 32,       // bits of an answer
    parameter PENDING_WIDTH = 1         // up to 1 << PENDING_WIDTH reads wait for answers
)(
    input  wire                            clk,
    input  wire                            rst_n,           // synchronous, active low
    // Requesters
    input  wire [N_REQ-1:0]                req_valid,
    output wire [N_REQ-1:0]                req_ready,
    input  wire [N_REQ-1:0]                req_we,          // a write: no answer
    input  wire [N_REQ-1:0][REQ_WIDTH-1:0] req_fields,
    output wire [N_REQ-1:0]                rsp_valid,       // the answer to a read of r
    output wire [RSP_WIDTH-1:0]            rsp_data,        // ... to every requester
    // Target
    output wire                            tgt_req_valid,
    input  wire                            tgt_req_ready,
    output wire                            tgt_req_we,
    output wire [REQ_WIDTH-1:0]            tgt_req_fields,
    input  wire                            tgt_rsp_valid,
    input  wire [RSP_WIDTH-1:0]            tgt_rsp_data
);
    `DC_STATIC_ASSERT(a_sizes, N_REQ >= 1 && PENDING_WIDTH >= 1)

    localparam N = N_REQ;

    wire [N-1:0] arb_req;           // what the arbiter sees
    wire [N-1:0] grant;             // one-hot: the winner now
    wire [N-1:0] grant_q;           // the grant of the clock before
    wire         lock;              // an offer waits: keep its grant
    wire         lock_next;
    wire         any;               // a winner
    wire [N-1:0] reads;             // the requests that are reads
    wire [N-1:0] win_reads;
    wire         win_read;          // the winner's request is a read
    wire [N-1:0] win_writes;
    wire         full;              // reads waiting: no more
    wire         blocked;           // a read while full
    wire         blocked_n;
    wire         tgt_take;          // the target takes the winner's request now
    wire         tgt_take_n;
    wire         read_taken;
    wire [N-1:0] oldest;            // the requester of the oldest read waiting
    // Not needed: the Fifo's count and thresholds; empty is checked by an assertion.
    /* verilator lint_off UNUSEDSIGNAL */
    wire         empty;
    wire [PENDING_WIDTH:0] count;
    wire         almost_full, almost_empty;
    /* verilator lint_on UNUSEDSIGNAL */

    // @kb: rtl/lib/block/req_mux/design
    // The winner; kept while its offer waits.
    Mux2 #(N) u_mux2_arb_req(.in0(req_valid), .in1(grant_q), .sel(lock), .out(arb_req));
    if (N > 1) begin: g_arbiter
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

    // The request to the target: the winner's, unless it is a read while full.
    Inv  #(N) u_inv_reads(.in(req_we), .out(reads));
    And2 #(N) u_and2_win_reads(.in1(grant), .in2(reads), .out(win_reads));
    OrReduce #(N) u_or_reduce_win_read(.in(win_reads), .out(win_read));
    And2 #(1) u_and2_blocked(.in1(full), .in2(win_read), .out(blocked));
    Inv  #(1) u_inv_blocked(.in(blocked), .out(blocked_n));
    And2 #(1) u_and2_tgt_valid(.in1(any), .in2(blocked_n), .out(tgt_req_valid));
    And2 #(N) u_and2_win_writes(.in1(grant), .in2(req_we), .out(win_writes));
    OrReduce #(N) u_or_reduce_we(.in(win_writes), .out(tgt_req_we));
    MuxOneHot #(.N(N), .WIDTH(REQ_WIDTH)) u_mux_one_hot_fields(
        .in(req_fields), .sel(grant), .out(tgt_req_fields));
    And2 #(1) u_and2_take(.in1(tgt_req_valid), .in2(tgt_req_ready), .out(tgt_take));
    And2 #(N) u_and2_ready(.in1(grant), .in2({N{tgt_take}}), .out(req_ready));
    And2 #(1) u_and2_read_taken(.in1(tgt_take), .in2(win_read), .out(read_taken));

    // The owners of the reads waiting; the answer to the oldest.
    Fifo #(.ADDR_WIDTH(PENDING_WIDTH), .DATA_WIDTH(N)) u_fifo_owner(
        .clk, .rst_n, .write(read_taken), .data_in(grant), .read(tgt_rsp_valid),
        .data_out(oldest), .empty, .full, .count, .almost_full, .almost_empty);
    And2 #(N) u_and2_rsp(.in1(oldest), .in2({N{tgt_rsp_valid}}), .out(rsp_valid));
    assign rsp_data = tgt_rsp_data;

    // See the behave version.
    `DC_ASSERT(a_one_grant, $onehot0(grant))
    `DC_ASSERT_NEXT(a_grant_held, tgt_req_valid && !tgt_req_ready, $stable(grant))
    `DC_ASSERT(a_answer_expected, !tgt_rsp_valid || !empty)

endmodule

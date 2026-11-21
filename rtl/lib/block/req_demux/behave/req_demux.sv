/* Request demultiplexer: one request channel to one of N_TARGETS targets by a one-hot
 * select, the answers back in order.
 *
 * The channel is the library's (the register port, the caches' memory sides): requests on
 * valid/ready, taken at a rising edge with valid=1 and ready=1; a request with req_rsp=1
 * (a read, an AMO, a write that asks for an answer) is answered by rsp_valid one or more
 * clocks after its target took it (no ready: every answer is taken), req_len + 1 answers
 * for a burst (kb rtl/lib/block/bursts: exactly that many, in order); one with req_rsp=0 (a
 * posted write) gets no answer. Whether a request reads or writes does not matter here,
 * only whether it is answered. req_sel names the target, exactly one bit (AddrDecode's
 * selects, its miss among them for the default target). Only valid and ready are routed:
 * the fields of the request (we, address, data, strobes, size) go to every target by the
 * caller's wires, a target ignores them without its valid. The answer is the one of the
 * target whose answers are waiting (owner).
 *
 * Order: a target answers in order; answers of two targets could pass each other, so a
 * request to another target than the one with answers waiting waits until they are back
 * (busy and another target), and a request that wants answers waits until all of them fit
 * below 1 << PENDING_WIDTH answers waiting (a burst bigger than that never fits:
 * a_len_fits). PENDING_WIDTH counts answers here (a burst's beats), where ReqMux's counts
 * requests (each with all its answers): size the two apart. Requests to the same target
 * flow on. req_ready is the selected target's ready when the request does not wait: it
 * follows the targets' readies and the select without a flop (allowed: valid never depends
 * on ready).
 *
 *   req_valid, req_sel --> blocked? (busy and another target, or full and req_rsp)
 *                      --> tgt_req_valid = req_sel when valid and not blocked
 *   req_ready <-- the selected tgt_req_ready, not blocked
 *   rsp_valid, rsp_data <-- the owner's answer      pending: answers asked, not back
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
    // @kb: rtl/lib/block/answered_writes
    input  wire                                req_rsp,         // wants an answer
    // @kb: rtl/lib/block/bursts
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
    // Bits of pending + req_len + 1.
    localparam SW = ((PENDING_WIDTH + 1 > LEN_WIDTH) ? PENDING_WIDTH + 1 : LEN_WIDTH) + 1;

    logic [PENDING_WIDTH:0] pending;    // answers that requests taken still wait for
    logic [SW-1:0]          need;       // ... with all of this request's
    logic [N_TARGETS-1:0]   owner;      // their target (meaningful while pending)
    logic                   busy;       // answers wait
    logic                   other;      // the request is for another target than owner
    logic                   blocked;    // the request waits
    logic                   ask_taken;  // a request that wants an answer is taken now

    // The answers of one target at a time: a request to another waits for them.
    // @kb: rtl/lib/block/req_demux/design
    assign busy      = pending != '0;
    assign other     = (req_sel & ~owner) != '0;
    assign need      = SW'(pending) + SW'(req_len) + SW'(1);
    assign blocked   = (busy && other) || (req_rsp && need > SW'(MAX));
    assign req_ready = !blocked && (tgt_req_ready & req_sel) != '0;
    assign tgt_req_valid = (req_valid && !blocked) ? req_sel : '0;
    assign ask_taken = req_valid && req_ready && req_rsp;

    always_ff @(posedge clk)
        if (!rst_n)
            pending <= '0;
        else
            pending <= pending + (ask_taken ? (PENDING_WIDTH+1)'(req_len) + 1'b1 : '0)
                               - (PENDING_WIDTH+1)'(rsp_valid);

    always_ff @(posedge clk)
        if (ask_taken)
            owner <= req_sel;

    // The owner's answer.
    function automatic logic [RSP_WIDTH-1:0] answer_of(
            input logic [N_TARGETS-1:0][RSP_WIDTH-1:0] d, input logic [N_TARGETS-1:0] s);
        logic [RSP_WIDTH-1:0] a;
        a = '0;
        for (int t = 0; t < N_TARGETS; t++)
            if (s[t])
                a = a | d[t];
        return a;
    endfunction

    assign rsp_valid = (tgt_rsp_valid & owner) != '0;
    assign rsp_data  = answer_of(tgt_rsp_data, owner);

    // A request names one target; a burst fits below the count; answers come only from the
    // owner, while answers wait.
    `DC_ASSERT(a_one_target, !req_valid || $onehot(req_sel))
    `DC_ASSERT(a_len_fits, !(req_valid && req_rsp && SW'(req_len) + SW'(1) > SW'(MAX)))
    `DC_ASSERT(a_answer_expected, tgt_rsp_valid == '0 || (busy && $onehot(tgt_rsp_valid) &&
                                                          (tgt_rsp_valid & ~owner) == '0))

endmodule

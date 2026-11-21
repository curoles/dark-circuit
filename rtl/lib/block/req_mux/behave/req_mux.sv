/* Request multiplexer: N_REQ request channels to one target, round-robin or by fixed
 * priority, the answers back to their requesters in order; behavioral.
 *
 * The channels are the library's (the register port, the caches' memory sides, DmaMover's):
 * requests on valid/ready, an offer not taken stays the same; a request with req_rsp=1 (a
 * read, an AMO, a write that asks for an answer) is answered by rsp_valid one or more
 * clocks after the target took it, in order (no ready: every answer is taken), req_len + 1
 * answers for a burst (kb rtl/lib/block/bursts: exactly that many, in order; the target
 * learns req_len from the fields the caller packs); one with req_rsp=0 (a posted write)
 * gets no answer. we and rsp pass to the target as they are; a request's other fields
 * (address, size, data, strobes, ...) travel as one vector of REQ_WIDTH bits, packed by the
 * caller. The requesters compete round-robin (FIXED_PRIO=0) or by fixed priority
 * (FIXED_PRIO=1: requester 0 first, then 1, ...; the lowest number offering wins, nothing
 * rotates; for a requester that must never wait for the others while the target is ready,
 * as a core's data port at its scratchpad, kb rtl/lib/block/req_mux/fixed_priority: the
 * others get the clocks it leaves free); the winner's request goes to the target as it
 * comes, with no buffer: a request taken here is taken by the target in the same clock, so
 * what one requester does stays in its order at the target, and a request is at the target
 * before anything its requester sends later. While the target does not take an offer, the
 * requester of that offer keeps the grant (the arbiter sees only its request), so the
 * target's offer stays the one of that requester, whose offer stays the same by the rules
 * (fields a request does not use, as a read's data, may change: they pass as they come);
 * with fixed priority too, so a waiting offer keeps the target even from requester 0. Each
 * request taken with req_rsp leaves its requester's number and its req_len in a FIFO of
 * 1 << PENDING_WIDTH entries; the target's answers go to the oldest (rsp_valid of that
 * requester; rsp_data to all), which leaves the FIFO with its last answer (a count of its
 * answers so far), so every requester gets its answers in order. A request with req_rsp
 * waits while the FIFO is full. PENDING_WIDTH counts requests here (each with all its
 * req_len + 1 answers), where ReqDemux's counts answers: size the two apart. req_ready
 * follows the requests and the target's ready without a flop (allowed: valid never depends
 * on ready).
 *
 *   req[0..N-1] --RoundRobinArbiter (kept while the offer waits)--> the winner --> target
 *   taken with req_rsp --> FIFO of requester numbers --oldest--> rsp_valid of that one
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
    // @kb: rtl/lib/block/answered_writes
    input  wire [N_REQ-1:0]                req_rsp,         // wants an answer
    // @kb: rtl/lib/block/bursts
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

    localparam N     = N_REQ;
    localparam DEPTH = 1 << PENDING_WIDTH;

    logic [N-1:0]         lock_grant;   // the grant of an offer the target did not take
    logic                 lock;         // ... kept
    logic [N-1:0]         last;         // the requesters below the last winner come first
    logic [N-1:0]         order;        // one-hot: the winner by the order, unlocked
    logic [N-1:0]         grant;        // one-hot: the winner now
    logic [N-1:0]         owner [DEPTH];    // requester of each answer waiting, oldest first
    logic [LEN_WIDTH-1:0] owner_len [DEPTH];    // ... its answers - 1
    logic [LEN_WIDTH-1:0] beat;         // the oldest's answers so far
    logic                 last_beat;    // the answer now is the oldest's last
    logic                 pop_owner;    // ... so it leaves the FIFO
    logic [PENDING_WIDTH:0] count;      // answers waiting
    logic                 full;
    logic                 win_ask;      // the winner's request wants an answer
    logic                 tgt_take;     // the target takes the winner's request now
    logic                 ask_taken;

    // Round-robin: the highest requester below the last winner, else the highest.
    function automatic logic [N-1:0] pick(input logic [N-1:0] r, input logic [N-1:0] below);
        logic [N-1:0] p;
        p = '0;
        for (int i = 0; i < N; i++)
            if (r[i])
                p = N'(1) << i;
        for (int i = 0; i < N; i++)
            if (r[i] && below[i])
                p = N'(1) << i;
        return p;
    endfunction

    // Fixed priority: the lowest requester offering.
    function automatic logic [N-1:0] first(input logic [N-1:0] r);
        logic [N-1:0] p;
        p = '0;
        for (int i = N - 1; i >= 0; i--)
            if (r[i])
                p = N'(1) << i;
        return p;
    endfunction

    // The req_len of the one-hot winner.
    function automatic logic [LEN_WIDTH-1:0] len_of(
            input logic [N-1:0][LEN_WIDTH-1:0] l, input logic [N-1:0] g);
        logic [LEN_WIDTH-1:0] x;
        x = '0;
        for (int i = 0; i < N; i++)
            if (g[i])
                x = x | l[i];
        return x;
    endfunction

    // The fields of the one-hot winner.
    function automatic logic [REQ_WIDTH-1:0] fields_of(
            input logic [N-1:0][REQ_WIDTH-1:0] f, input logic [N-1:0] g);
        logic [REQ_WIDTH-1:0] x;
        x = '0;
        for (int i = 0; i < N; i++)
            if (g[i])
                x = x | f[i];
        return x;
    endfunction

    // @kb: rtl/lib/block/req_mux/design
    // @kb: rtl/lib/block/req_mux/fixed_priority
    assign order      = (FIXED_PRIO != 0) ? first(req_valid) : pick(req_valid, last);
    assign grant      = lock ? lock_grant : order;
    assign full       = count == (PENDING_WIDTH+1)'(DEPTH);
    assign win_ask    = (grant & req_rsp) != '0;
    assign tgt_req_valid  = grant != '0 && !(full && win_ask);
    assign tgt_req_we     = (grant & req_we) != '0;
    assign tgt_req_rsp    = win_ask;
    assign tgt_req_fields = fields_of(req_fields, grant);
    assign tgt_take   = tgt_req_valid && tgt_req_ready;
    assign req_ready  = tgt_take ? grant : '0;
    assign ask_taken  = tgt_take && win_ask;

    always_ff @(posedge clk)
        if (!rst_n) begin
            lock <= 1'b0;
            last <= '1;
        end else begin
            lock <= grant != '0 && !tgt_take;
            if (tgt_take)                                   // the order moves on
                for (int i = 0; i < N; i++)
                    last[i] <= (grant >> (i + 1)) != '0;
        end

    always_ff @(posedge clk)
        lock_grant <= grant;

    // The requesters of the answers waiting, oldest at 0; the oldest leaves with its last
    // answer.
    // @kb: rtl/lib/block/bursts
    assign last_beat = beat == owner_len[0];
    assign pop_owner = tgt_rsp_valid && last_beat;

    always_ff @(posedge clk)
        if (!rst_n) begin
            count <= '0;
            beat  <= '0;
        end else begin
            for (int i = 0; i < DEPTH - 1; i++)
                if (pop_owner) begin
                    owner[i]     <= owner[i + 1];
                    owner_len[i] <= owner_len[i + 1];
                end
            if (ask_taken) begin
                owner[int'(count) - (pop_owner ? 1 : 0)]     <= grant;
                owner_len[int'(count) - (pop_owner ? 1 : 0)] <= len_of(req_len, grant);
            end
            count <= count + (PENDING_WIDTH+1)'(ask_taken) - (PENDING_WIDTH+1)'(pop_owner);
            if (tgt_rsp_valid)
                beat <= last_beat ? '0 : beat + 1'b1;
        end

    assign rsp_valid = tgt_rsp_valid ? owner[0] : '0;
    assign rsp_data  = tgt_rsp_data;

    // One winner; the requester of an offer the target did not take keeps the grant (its
    // offer stays the same by the rules, the requester's part: fields a request does not
    // use, a read's data, may change); answers only while answers wait.
    `DC_ASSERT(a_one_grant, $onehot0(grant))
    `DC_ASSERT_NEXT(a_grant_held, tgt_req_valid && !tgt_req_ready, $stable(grant))
    `DC_ASSERT(a_answer_expected, !tgt_rsp_valid || count != '0)

endmodule

/* Request multiplexer: N_REQ request channels to one target, round-robin, the answers back to
 * their requesters in order; behavioral.
 *
 * The channels are the library's (the register port, the caches' memory sides, DmaMover's):
 * requests on valid/ready, an offer not taken stays the same; a read is answered by
 * rsp_valid one or more clocks after the target took it, in order (no ready: every answer is
 * taken); a write gets no answer. A request's fields other than we (address, size, data,
 * strobes, ...) travel as one vector of REQ_WIDTH bits, packed by the caller. The requesters
 * compete round-robin; the winner's request goes to the target as it comes, with no buffer:
 * a request taken here is taken by the target in the same clock, so what one requester does
 * stays in its order at the target, and a request is at the target before anything its
 * requester sends later. While the target does not take an offer, the requester of that
 * offer keeps the grant (the arbiter sees only its request), so the target's offer stays
 * the one of that requester, whose offer stays the same by the rules (fields a request
 * does not use, as a read's data, may change: they pass as they come). Each read taken
 * leaves its requester's number in a FIFO of 1 << PENDING_WIDTH entries; the target's
 * answer goes to the oldest (rsp_valid of that requester; rsp_data to all), so every
 * requester gets its answers in order. A read waits while the FIFO is full. req_ready
 * follows the requests and the target's ready without a flop (allowed: valid never depends
 * on ready).
 *
 *   req[0..N-1] --RoundRobinArbiter (kept while the offer waits)--> the winner --> target
 *   read taken --> FIFO of requester numbers --oldest--> rsp_valid of that requester
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

    localparam N     = N_REQ;
    localparam DEPTH = 1 << PENDING_WIDTH;

    logic [N-1:0]         lock_grant;   // the grant of an offer the target did not take
    logic                 lock;         // ... kept
    logic [N-1:0]         last;         // the requesters below the last winner come first
    logic [N-1:0]         grant;        // one-hot: the winner now
    logic [N-1:0]         owner [DEPTH];    // requester of each read waiting, oldest first
    logic [PENDING_WIDTH:0] count;      // reads waiting
    logic                 full;
    logic                 win_read;     // the winner's request is a read
    logic                 tgt_take;     // the target takes the winner's request now
    logic                 read_taken;

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
    assign grant      = lock ? lock_grant : pick(req_valid, last);
    assign full       = count == (PENDING_WIDTH+1)'(DEPTH);
    assign win_read   = (grant & ~req_we) != '0;
    assign tgt_req_valid  = grant != '0 && !(full && win_read);
    assign tgt_req_we     = (grant & req_we) != '0;
    assign tgt_req_fields = fields_of(req_fields, grant);
    assign tgt_take   = tgt_req_valid && tgt_req_ready;
    assign req_ready  = tgt_take ? grant : '0;
    assign read_taken = tgt_take && win_read;

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

    // The requesters of the reads waiting, oldest at 0.
    always_ff @(posedge clk)
        if (!rst_n)
            count <= '0;
        else begin
            for (int i = 0; i < DEPTH - 1; i++)
                if (tgt_rsp_valid)
                    owner[i] <= owner[i + 1];
            if (read_taken)
                owner[int'(count) - (tgt_rsp_valid ? 1 : 0)] <= grant;
            count <= count + (PENDING_WIDTH+1)'(read_taken) - (PENDING_WIDTH+1)'(tgt_rsp_valid);
        end

    assign rsp_valid = tgt_rsp_valid ? owner[0] : '0;
    assign rsp_data  = tgt_rsp_data;

    // One winner; the requester of an offer the target did not take keeps the grant (its
    // offer stays the same by the rules, the requester's part: fields a request does not
    // use, a read's data, may change); answers only for reads waiting.
    `DC_ASSERT(a_one_grant, $onehot0(grant))
    `DC_ASSERT_NEXT(a_grant_held, tgt_req_valid && !tgt_req_ready, $stable(grant))
    `DC_ASSERT(a_answer_expected, !tgt_rsp_valid || count != '0)

endmodule

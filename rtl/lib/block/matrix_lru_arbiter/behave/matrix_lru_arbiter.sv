/* Matrix arbiter, least recently granted first, behavioral: one of N requesters wins.
 *
 * The order of the requesters, from the least to the most recently granted, is an AgeMatrix
 * (one bit per pair) in a register; grant is one-hot: the requester granted longest ago, 0 when
 * there is no request. advance=1 uses the grant: its winner becomes the most recently granted;
 * advance=0 leaves the order, so the same requests get the same grant (a grant an allocator did
 * not use). After reset requester 0 counts as the least recently granted, N-1 as the most. A
 * requester that keeps requesting wins within N - 1 used grants of the others. Same ports as
 * RoundRobinArbiter, which orders by position instead of time.
 *
 *   req --> AgeMatrix (select_mask) --> select_oldest = grant
 *              ^ ages      | ages_next      | index (touch_index), touch: advance and a grant
 *              +-- register <---------------+
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "dark_circuit_assert.svh"

module MatrixLruArbiter #(
    parameter  N          = 4,                  // requesters, at least 2
    localparam W          = $clog2(N),          // bits of an index
    localparam AGES_WIDTH = N * (N - 1) / 2     // the order: a bit per pair
)(
    input  wire         clk,
    input  wire         rst_n,                  // synchronous reset, active low
    input  wire [N-1:0] req,
    input  wire         advance,                // the grant is used: the order moves on
    output wire [N-1:0] grant                   // one-hot winner, 0 when no request
);
    `DC_STATIC_ASSERT(a_n, N >= 2)

    logic [AGES_WIDTH-1:0] ages_q;
    logic [AGES_WIDTH-1:0] ages_next;

    // Index of the set bit of one-hot g.
    function automatic logic [W-1:0] index_of(input logic [N-1:0] g);
        logic [W-1:0] k;
        k = '0;
        for (int i = 0; i < N; i++)
            if (g[i])
                k = W'(i);
        return k;
    endfunction

    AgeMatrix #(.SIZE(N)) u_age_matrix(
        .ages(ages_q), .touch(advance && |grant), .touch_index(index_of(grant)), .ages_next,
        .select_mask(req), .select_oldest(grant));

    always_ff @(posedge clk)
        if (!rst_n) ages_q <= '0;
        else        ages_q <= ages_next;

endmodule

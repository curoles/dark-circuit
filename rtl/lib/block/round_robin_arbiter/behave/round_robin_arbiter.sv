/* Round-robin arbiter, behavioral: one of N requesters wins, the priority rotates.
 *
 * grant is one-hot: the highest requester below the last winner, else (none below it) the
 * highest requester; 0 when there is no request. advance=1 uses the grant: its winner becomes
 * the last winner, so the requesters below it come first next time (the priority rotates
 * downward); advance=0 leaves the order, so the same requests get the same grant (a grant an
 * allocator did not use). After reset every requester counts as below the last winner. A
 * requester that keeps requesting wins within N - 1 used grants of the others. Same ports as
 * MatrixLruArbiter, which orders by time instead of position.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "dark_circuit_assert.svh"

module RoundRobinArbiter #(
    parameter N = 4                         // requesters, at least 2
)(
    input  wire         clk,
    input  wire         rst_n,              // synchronous reset, active low
    input  wire [N-1:0] req,
    input  wire         advance,            // the grant is used: the order moves on
    output wire [N-1:0] grant               // one-hot winner, 0 when no request
);
    `DC_STATIC_ASSERT(a_n, N >= 2)

    logic [N-1:0] below_q;                  // requesters below the last winner: they come first

    // One-hot: the highest set bit of r, 0 when r is 0.
    function automatic logic [N-1:0] highest(input logic [N-1:0] r);
        logic [N-1:0] h;
        h = '0;
        for (int i = 0; i < N; i++)
            if (r[i])
                h = N'(1) << i;
        return h;
    endfunction

    // The bits below the set bit of one-hot g.
    function automatic logic [N-1:0] below(input logic [N-1:0] g);
        logic [N-1:0] b;
        b = '0;
        for (int i = 0; i < N - 1; i++)
            b[i] = |(g >> (i + 1));
        return b;
    endfunction

    assign grant = (|(req & below_q)) ? highest(req & below_q) : highest(req);

    always_ff @(posedge clk)
        if (!rst_n)                  below_q <= '1;
        else if (advance && |grant)  below_q <= below(grant);

endmodule

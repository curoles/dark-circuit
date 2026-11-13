/* Prefix count, behavioral: for every bit of in, the number of ones below it; combinational.
 *
 * prefix[k] is the number of ones in in[k-1:0] (0 for k = 0), total the number of ones in
 * all of in. Both have CW bits, enough for 0..WIDTH. WIDTH is 1 or more, not only a power
 * of 2.
 *
 * For example, WIDTH = 8:
 *   in (bit 0 first)  0 1 0 0 1 1 0 1
 *   prefix            0 0 1 1 1 2 3 3     total 4
 *
 * A one's prefix is its place among the ones: the 1 at bit 4 is the second one (place 1).
 * Uses: StreamCompact (the zeros below a one are how far it moves), the rank of a request
 * among the active ones, a bit vector to slots.
 *
 * The behave version adds bit by bit from bit 0 up; the struct version is a parallel prefix
 * of counts, log2(WIDTH) levels of adders.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
`include "dark_circuit_assert.svh"

module PrefixCount #(
    parameter  WIDTH = 32,
    localparam CW    = $clog2(WIDTH + 1)        // bits of a count 0..WIDTH
)(
    input  wire [WIDTH-1:0]         in,
    output wire [WIDTH-1:0][CW-1:0] prefix,     // prefix[k]: ones in in[k-1:0]
    output wire [CW-1:0]            total       // ones in in
);
    `DC_STATIC_ASSERT(a_width, WIDTH >= 1)

    // {total, prefix}: the running count before every bit, then after the last one.
    // A function, not always_comb: Icarus warns about constant selects in always_* processes.
    function automatic [(WIDTH+1)*CW-1:0] counts(input [WIDTH-1:0] v);
        logic [WIDTH-1:0][CW-1:0] p;
        logic [CW-1:0]            n;
        n = '0;
        for (int k = 0; k < WIDTH; k++) begin
            p[k] = n;
            n    = n + CW'(v[k]);
        end
        return {n, p};
    endfunction

    assign {total, prefix} = counts(in);

endmodule

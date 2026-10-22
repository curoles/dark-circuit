/* Wallace tree multiplier: product = a * b, unsigned, made of blocks, parts and gates.
 *
 * Same ports and result as CsaMultiplier. Partial product row j is a & b[j] (And2),
 * shifted left by j. A WallaceTree reduces the WIDTH rows to two (8 layers, one full adder
 * deep each, for WIDTH=32, instead of CsaMultiplier's 32 rows); a KoggeStoneAdder adds
 * them.
 *
 * - C. S. Wallace, A Suggestion for a Fast Multiplier, IEEE Transactions on Electronic
 *   Computers, 1964.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module WallaceMultiplier #(
    parameter WIDTH = 32
)(
    input  wire [WIDTH-1:0]   a,
    input  wire [WIDTH-1:0]   b,
    output wire [2*WIDTH-1:0] product
);
    localparam P = 2 * WIDTH;

    wire [P-1:0] rows [WIDTH];  // partial products: row j = (a & b[j]) << j
    wire [P-1:0] sum;           // the tree's two rows
    wire [P-1:0] carry;
    // The product fits in P bits: no carry out.
    /* verilator lint_off UNUSEDSIGNAL */
    wire         co;
    /* verilator lint_on UNUSEDSIGNAL */

    // Partial products (a shift by a constant is wiring).
    for (genvar j = 0; j < WIDTH; j++) begin : g_pp
        wire [WIDTH-1:0] pp;        // a & b[j]
        wire [P-1:0]     pp_wide;   // pp in P bits
        And2 #(WIDTH) u_and2(.in1(a), .in2({WIDTH{b[j]}}), .out(pp));
        assign pp_wide = {{WIDTH{1'b0}}, pp};
        assign rows[j] = pp_wide << j;
    end

    WallaceTree #(.ROWS(WIDTH), .WIDTH(P)) u_wallace_tree(.rows, .sum, .carry);
    KoggeStoneAdder #(P) u_kogge_stone_adder(
        .in1(sum), .in2(carry), .ci(1'b0), .co, .sum(product));

endmodule

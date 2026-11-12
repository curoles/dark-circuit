/* Multiplier rows: the partial products of a * b, each operand signed or unsigned, as W + 3
 * rows of OUT bits whose sum modulo 2^OUT is the product.
 *
 * A negative signed operand is its unsigned value minus 2^W, so the signed product is the
 * unsigned one minus (a_neg ? b : 0) << W minus (b_neg ? a : 0) << W plus, when both are
 * negative, 1 << 2W. With x, y the two middle terms, -x - y = ~x + ~y + 2 in any width: rows
 * 0 to W-1 are the unsigned partial products (a & b[j]) << j, rows W and W+1 are ~x and ~y
 * shifted to bit W with ones above them (the complement in OUT bits, not only in 2W), row
 * W+2 is 2 << W and, when OUT > 2W, a_neg & b_neg at bit 2W. With OUT = 2W these are
 * Int32Mul's rows (1 << 2W drops out); with OUT > 2W the product comes out sign- or
 * zero-extended, so the rows of several pieces can go into one adder tree at their weights
 * (a 16 x 16 product from four 8 x 8 pieces, a dot product of byte lanes). Made of gates: the
 * user adds the rows (a WallaceTree, then an adder).
 *
 *   a, b --> And2 per bit of b --> rows 0..W-1
 *   a_signed & a[W-1] --> x = b or 0 --> ~x << W (ones above) --> row W;  y likewise --> W+1
 *   2 << W, and a_neg & b_neg at bit 2W (OUT > 2W) --> row W+2
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
`include "dark_circuit_assert.svh"

module MulRows #(
    parameter int W   = 8,      // operand width
    parameter int OUT = 2 * W   // row width: the product modulo 2^OUT, 2W or more
)(
    input  wire [W-1:0]   a,
    input  wire [W-1:0]   b,
    input  wire           a_signed,
    input  wire           b_signed,
    output wire [OUT-1:0] rows [W + 3]  // their sum modulo 2^OUT is a * b
);
    `DC_STATIC_ASSERT(a_out, OUT >= 2 * W)

    wire         a_neg;     // a is signed and negative
    wire         b_neg;
    wire [W-1:0] x;         // a_neg ? b : 0
    wire [W-1:0] y;         // b_neg ? a : 0
    wire [W-1:0] x_inv;
    wire [W-1:0] y_inv;

    And2 #(1) u_and2_a_neg(.in1(a_signed), .in2(a[W-1]), .out(a_neg));
    And2 #(1) u_and2_b_neg(.in1(b_signed), .in2(b[W-1]), .out(b_neg));
    And2 #(W) u_and2_x(.in1(b), .in2({W{a_neg}}), .out(x));
    And2 #(W) u_and2_y(.in1(a), .in2({W{b_neg}}), .out(y));
    Inv  #(W) u_inv_x(.in(x), .out(x_inv));
    Inv  #(W) u_inv_y(.in(y), .out(y_inv));

    // @kb: rtl/lib/numeric/packed/mul
    // Partial products of the unsigned values (a shift by a constant is wiring).
    for (genvar j = 0; j < W; j++) begin : g_pp
        wire [W-1:0]   pp;          // a & b[j]
        wire [OUT-1:0] pp_wide;     // pp in OUT bits
        And2 #(W) u_and2(.in1(a), .in2({W{b[j]}}), .out(pp));
        assign pp_wide = OUT'(pp);
        assign rows[j] = pp_wide << j;
    end

    // Correction of the signed operands at bit W: -x - y = ~x + ~y + 2, the complements in
    // OUT bits (ones above bit 2W - 1); and 1 << 2W when both are negative, which only a row
    // wider than 2W keeps (two disjoint bits: wiring).
    if (OUT > 2 * W) begin : g_above
        wire both_neg;      // a_neg and b_neg
        And2 #(1) u_and2_both_neg(.in1(a_neg), .in2(b_neg), .out(both_neg));
        assign rows[W]     = {{(OUT - 2 * W){1'b1}}, x_inv, {W{1'b0}}};
        assign rows[W + 1] = {{(OUT - 2 * W){1'b1}}, y_inv, {W{1'b0}}};
        assign rows[W + 2] = (OUT'(both_neg) << (2 * W)) | (OUT'(2) << W);
    end else begin : g_exact
        assign rows[W]     = {x_inv, {W{1'b0}}};
        assign rows[W + 1] = {y_inv, {W{1'b0}}};
        assign rows[W + 2] = OUT'(2) << W;
    end

endmodule

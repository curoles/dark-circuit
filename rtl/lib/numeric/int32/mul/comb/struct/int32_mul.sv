/* 32-bit integer multiplier: product = a * b, each operand signed or unsigned,
 * combinational, made of blocks, parts and gates.
 *
 * Same ports and result as the behave version. CsaMultiplier gives the product p of
 * the unsigned values; a negative signed operand is its unsigned value minus 2^32,
 * so modulo 2^64 only the upper half changes:
 *   hi = p_hi - (a_neg ? b : 0) - (b_neg ? a : 0)  (mod 2^32),   lo = p_lo.
 * The two subtractions are one CarrySaveAdder and one RippleCarryAdder: with x, y the
 * two terms, p_hi - x - y = p_hi + ~x + ~y + 2 = ps + {sc, 1} + 1, where ps and sc
 * are the partial sum and the carries of the CarrySaveAdder of p_hi, ~x and ~y.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module Int32Mul (
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire        a_signed,
    input  wire        b_signed,
    output wire [63:0] product
);
    wire [63:0] p;          // product of the unsigned values
    wire        a_neg;      // a is signed and negative
    wire        b_neg;
    wire [31:0] x;          // a_neg ? b : 0
    wire [31:0] y;          // b_neg ? a : 0
    wire [31:0] x_inv;
    wire [31:0] y_inv;
    wire [31:0] ps;         // partial sum of the CarrySaveAdder
    // Carries of the CarrySaveAdder, weight 2: the top one and the carry out of the final
    // adder have weight 2^64, they are not part of the 64-bit product.
    /* verilator lint_off UNUSEDSIGNAL */
    wire [31:0] sc;
    wire        co;
    /* verilator lint_on UNUSEDSIGNAL */

    CsaMultiplier #(.WIDTH(32)) u_csa_multiplier(.a, .b, .product(p));

    And2 #(1)  u_and2_a_neg(.in1(a_signed), .in2(a[31]), .out(a_neg));
    And2 #(1)  u_and2_b_neg(.in1(b_signed), .in2(b[31]), .out(b_neg));
    And2 #(32) u_and2_x(.in1(b), .in2({32{a_neg}}), .out(x));
    And2 #(32) u_and2_y(.in1(a), .in2({32{b_neg}}), .out(y));
    Inv  #(32) u_inv_x(.in(x), .out(x_inv));
    Inv  #(32) u_inv_y(.in(y), .out(y_inv));

    CarrySaveAdder #(.WIDTH(32)) u_carry_save_adder(
        .in1(p[63:32]), .in2(x_inv), .in3(y_inv), .ps, .sc);
    RippleCarryAdder #(.WIDTH(32)) u_ripple_carry_adder(
        .in1(ps), .in2({sc[30:0], 1'b1}), .ci(1'b1), .co, .sum(product[63:32]));

    assign product[31:0] = p[31:0];

endmodule

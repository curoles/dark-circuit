/* 32-bit integer multiplier: product = a * b, each operand signed or unsigned,
 * combinational, made of blocks, parts and gates.
 *
 * Same ports and result as the behave version. A negative signed operand is its
 * unsigned value minus 2^32, so modulo 2^64 only the upper half of the unsigned product
 * changes: hi = p_hi - (a_neg ? b : 0) - (b_neg ? a : 0). With x, y the two terms,
 * -x - y = ~x + ~y + 2 (mod 2^32). One WallaceTree adds 35 rows: the 32 partial products
 * (a & b[j]) << j of the unsigned product, and ~x, ~y and 2 shifted to the upper half
 * (<< 32); 35 rows take as many layers as 32 (8). One KoggeStoneAdder adds the tree's two
 * rows; carries above bit 63 are dropped: the product is mod 2^64.
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
    wire        a_neg;      // a is signed and negative
    wire        b_neg;
    wire [31:0] x;          // a_neg ? b : 0
    wire [31:0] y;          // b_neg ? a : 0
    wire [31:0] x_inv;
    wire [31:0] y_inv;
    wire [63:0] rows [35];  // partial products, then ~x, ~y and 2 in the upper half
    wire [63:0] sum;        // the tree's two rows
    wire [63:0] carry;
    // The carry out has weight 2^64: not part of the 64-bit product.
    /* verilator lint_off UNUSEDSIGNAL */
    wire        co;
    /* verilator lint_on UNUSEDSIGNAL */

    And2 #(1)  u_and2_a_neg(.in1(a_signed), .in2(a[31]), .out(a_neg));
    And2 #(1)  u_and2_b_neg(.in1(b_signed), .in2(b[31]), .out(b_neg));
    And2 #(32) u_and2_x(.in1(b), .in2({32{a_neg}}), .out(x));
    And2 #(32) u_and2_y(.in1(a), .in2({32{b_neg}}), .out(y));
    Inv  #(32) u_inv_x(.in(x), .out(x_inv));
    Inv  #(32) u_inv_y(.in(y), .out(y_inv));

    // Partial products of the unsigned values (a shift by a constant is wiring).
    for (genvar j = 0; j < 32; j++) begin : g_pp
        wire [31:0] pp;         // a & b[j]
        wire [63:0] pp_wide;    // pp in 64 bits
        And2 #(32) u_and2(.in1(a), .in2({32{b[j]}}), .out(pp));
        assign pp_wide = {32'b0, pp};
        assign rows[j] = pp_wide << j;
    end

    // Correction of the signed operands, in the upper half: -x - y = ~x + ~y + 2.
    assign rows[32] = {x_inv, 32'b0};
    assign rows[33] = {y_inv, 32'b0};
    assign rows[34] = {30'b0, 2'b10, 32'b0};   // 2 << 32

    WallaceTree #(.ROWS(35), .WIDTH(64)) u_wallace_tree(.rows, .sum, .carry);
    KoggeStoneAdder #(.WIDTH(64)) u_kogge_stone_adder(
        .in1(sum), .in2(carry), .ci(1'b0), .co, .sum(product));

endmodule

/* Booth Encoding cell with Verilog primitives, TSMC-style cell BENC.
 *
 * The M2, M1, and M0 inputs are the three bits from the multiplier
 * that are used to derive the Partial Product.
 */
module BENC (
    input  wire M0,
    input  wire M1,
    input  wire M2,
    output wire S,
    output wire A,
    output wire X2
);

    wire m10_nand, m10_or, m2_n;

    nand u_nand_m10(m10_nand, M1, M0);
    nand u_nand_s(S, M2, m10_nand);

    not  u_not_m2(m2_n, M2);
    or   u_or_m10(m10_or, M1, M0);
    nand u_nand_a(A, m2_n, m10_or);

    xnor u_xnor_x2(X2, M1, M0);

endmodule

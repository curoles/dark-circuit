/* CMOS Booth Encoding cell, TSMC-style cell BENC.
 *
 * The M2, M1, and M0 inputs are the three bits from the multiplier
 * that are used to derive the Partial Product.
 *
 * S  = ~(M2 & ~(M1 & M0))  = ND2(M2, ND2(M1, M0))
 * A  = ~(~M2 & (M1 | M0))  = IND2(M2, OR2(M1, M0))
 * X2 = ~(M1 ^ M0)          = XNR2(M1, M0)
 */
module BENC (
    input  wire M0,
    input  wire M1,
    input  wire M2,
    output wire S,
    output wire A,
    output wire X2
);
    wire m10_nand, m10_or;

    ND2  u_nd2_m10(.A1(M1), .A2(M0), .ZN(m10_nand));
    ND2  u_nd2_s  (.A1(M2), .A2(m10_nand), .ZN(S));

    OR2  u_or2_m10(.A1(M1), .A2(M0), .Z(m10_or));
    IND2 u_ind2_a (.A1(M2), .B1(m10_or), .ZN(A));

    XNR2 u_xnr2_x2(.A1(M1), .A2(M0), .ZN(X2));

endmodule

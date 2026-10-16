/* Booth Multiplexer cell with Verilog primitive `not` and AOI22 cells, TSMC-style cell BML.
 *
 * Takes in two bits of the multiplicand at a time and generates the partial product
 * using other inputs that come in from the booth encoder cell BENC.
 *
 */
module BML (
    input  wire X2,
    input  wire A,
    input  wire S,
    input  wire M0,
    input  wire M1,
    output wire PP
);

    wire m1_sel_n;
    wire m0_sel_n;

    wire X2_n;
    wire A_n;
    wire S_n;
    wire M0_n;
    wire M1_n;

    not u_not_x2(X2_n, X2);
    not u_not_a (A_n,  A);
    not u_not_s (S_n,  S);
    not u_not_m0(M0_n, M0);
    not u_not_m1(M1_n, M1);

    AOI22 u_aoi22_0 (.A1(A_n), .A2(M1), .B1(S_n), .B2(M1_n), .ZN(m1_sel_n));

    AOI22 u_aoi22_1 (.A1(A_n), .A2(M0), .B1(S_n), .B2(M0_n), .ZN(m0_sel_n));

    AOI22 u_aoi22_2 (.A1(X2_n), .A2(m1_sel_n), .B1(X2), .B2(m0_sel_n), .ZN(PP));

endmodule

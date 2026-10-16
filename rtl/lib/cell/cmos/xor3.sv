/* CMOS 3-input XOR, TSMC-style cell XOR3.
 *
 * Two 2-input XOR cells.
 */
module XOR3 (
    input  wire A1,
    input  wire A2,
    input  wire A3,
    output wire Z
);
    wire xor12;
    XOR2 u_xor2_1(.A1(A1), .A2(A2), .Z(xor12));
    XOR2 u_xor2_2(.A1(xor12), .A2(A3), .Z(Z));

endmodule

/* CMOS Half Adder, TSMC-style cell HA1.
 *
 * XOR for sum, AND for carry.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module HA1 (
    input  wire A,
    input  wire B,
    output wire S,  // sum
    output wire CO  // carry out
);
    XOR2 u_xor2(.A1(A), .A2(B), .Z(S));
    AN2  u_an2(.A1(A), .A2(B), .Z(CO));

endmodule

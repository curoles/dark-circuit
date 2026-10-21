/* CMOS 2-input XNOR, TSMC-style cell XNR2.
 *
 * XOR followed by inverter.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module XNR2 (
    input  wire A1,
    input  wire A2,
    output wire ZN
);
    wire xor_output;
    XOR2 u_xor2(.A1(A1), .A2(A2), .Z(xor_output));
    INV  u_inv(.I(xor_output), .ZN(ZN));

endmodule

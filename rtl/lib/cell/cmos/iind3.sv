/* CMOS 3-input NAND with 2 inverted inputs, TSMC-style cell IIND3.
 *
 * Inverters on A1 and A2 followed by NAND.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module IIND3 (
    input  wire A1, // inverted
    input  wire A2, // inverted
    input  wire B1,
    output wire ZN
);
    wire a1_n, a2_n;
    INV u_inv_1(.I(A1), .ZN(a1_n));
    INV u_inv_2(.I(A2), .ZN(a2_n));
    ND3 u_nd3(.A1(a1_n), .A2(a2_n), .A3(B1), .ZN(ZN));

endmodule

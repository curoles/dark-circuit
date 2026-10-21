/* CMOS 2-input NAND with 1 inverted input, TSMC-style cell IND2.
 *
 * Inverter on A1 followed by NAND.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module IND2 (
    input  wire A1, // inverted
    input  wire B1,
    output wire ZN
);
    wire a1_n;
    INV u_inv(.I(A1), .ZN(a1_n));
    ND2 u_nd2(.A1(a1_n), .A2(B1), .ZN(ZN));

endmodule

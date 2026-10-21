/* CMOS 3-input NAND with 1 inverted input, TSMC-style cell IND3.
 *
 * Inverter on A1 followed by NAND.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module IND3 (
    input  wire A1, // inverted
    input  wire B1,
    input  wire B2,
    output wire ZN
);
    wire a1_n;
    INV u_inv(.I(A1), .ZN(a1_n));
    ND3 u_nd3(.A1(a1_n), .A2(B1), .A3(B2), .ZN(ZN));

endmodule

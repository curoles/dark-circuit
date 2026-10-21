/* CMOS 3-input AND, TSMC-style cell AN3.
 *
 * NAND followed by inverter.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module AN3 (
    input  wire A1,
    input  wire A2,
    input  wire A3,
    output wire Z
);
    wire nand_output;
    ND3 u_nd3(.A1(A1), .A2(A2), .A3(A3), .ZN(nand_output));
    INV u_inv(.I(nand_output), .ZN(Z));

endmodule

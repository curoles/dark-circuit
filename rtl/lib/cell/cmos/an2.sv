/* CMOS 2-input AND, TSMC-style cell AN2.
 *
 * NAND followed by inverter.
 */
module AN2 (
    input  wire A1,
    input  wire A2,
    output wire Z
);
    wire nand_output;
    ND2 u_nd2(.A1(A1), .A2(A2), .ZN(nand_output));
    INV u_inv(.I(nand_output), .ZN(Z));

endmodule

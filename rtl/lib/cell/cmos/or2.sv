/* CMOS 2-input OR, TSMC-style cell OR2.
 *
 * NOR followed by inverter.
 */
module OR2 (
    input  wire A1,
    input  wire A2,
    output wire Z
);
    wire nor_output;
    NR2 u_nr2(.A1(A1), .A2(A2), .ZN(nor_output));
    INV u_inv(.I(nor_output), .ZN(Z));

endmodule

/* CMOS 3-input OR, TSMC-style cell OR3.
 *
 * NOR followed by inverter.
 */
module OR3 (
    input  wire A1,
    input  wire A2,
    input  wire A3,
    output wire Z
);
    wire nor_output;
    NR3 u_nr3(.A1(A1), .A2(A2), .A3(A3), .ZN(nor_output));
    INV u_inv(.I(nor_output), .ZN(Z));

endmodule

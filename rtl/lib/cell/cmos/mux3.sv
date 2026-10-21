/* CMOS 3:1 Multiplexer, TSMC-style cell MUX3.
 *
 * Two MUX2 cells: S0 selects I1 or I0, then S1 selects I2.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module MUX3 (
    input  wire I0,
    input  wire I1,
    input  wire I2,
    input  wire S0,
    input  wire S1,
    output wire Z
);
    wire mux01;
    MUX2 u_mux2_01 (.I0(I0), .I1(I1), .S(S0), .Z(mux01));
    MUX2 u_mux2_out(.I0(mux01), .I1(I2), .S(S1), .Z(Z));

endmodule

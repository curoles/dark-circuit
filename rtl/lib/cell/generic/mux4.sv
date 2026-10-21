/* 4:1 Multiplexer, TSMC-style cell MUX4.
 *
 * {S1,S0} = k selects Ik.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module MUX4 (
    input  wire I0,
    input  wire I1,
    input  wire I2,
    input  wire I3,
    input  wire S0,
    input  wire S1,
    output wire Z
);

    assign Z = S1 ? (S0 ? I3 : I2) : (S0 ? I1 : I0);

endmodule

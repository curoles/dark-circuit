/* 3:1 Multiplexer, TSMC-style cell MUX3.
 *
 * S1 selects I2, otherwise S0 selects I1 or I0.
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

    assign Z = S1 ? I2 : (S0 ? I1 : I0);

endmodule

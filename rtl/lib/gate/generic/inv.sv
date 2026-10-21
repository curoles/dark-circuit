/* Inverter.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module Inv #(
    parameter WIDTH = 1
)(
    input  wire [WIDTH-1:0] in,  // to be inverted
    output wire [WIDTH-1:0] out  // out is inverted in
);

    assign out = ~in;

endmodule

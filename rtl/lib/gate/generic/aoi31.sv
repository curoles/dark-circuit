/* AND-OR-Invert, 3-Input AND Feeding NOR with 1 input.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module Aoi31 #(
    parameter WIDTH = 1
)(
    input  wire [WIDTH-1:0] in1,
    input  wire [WIDTH-1:0] in2,
    input  wire [WIDTH-1:0] in3,
    input  wire [WIDTH-1:0] in4,
    output wire [WIDTH-1:0] out
);

    assign out = ~(in4 | (in1 & in2 & in3));

endmodule

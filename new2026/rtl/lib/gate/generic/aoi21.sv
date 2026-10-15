/* AND-OR-Invert, out = ~((in1 & in2) | in3).
 *
 */
module Aoi21 #(
    parameter WIDTH = 1
)(
    input  wire [WIDTH-1:0] in1, // to be AND-ed with in2
    input  wire [WIDTH-1:0] in2, // to be AND-ed with in1
    input  wire [WIDTH-1:0] in3,
    output wire [WIDTH-1:0] out
);

    assign out = ~((in1 & in2) | in3);

endmodule

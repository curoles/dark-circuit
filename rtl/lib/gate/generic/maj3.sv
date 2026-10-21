/* 3-input Majority, out bit is 1 when at least 2 of 3 input bits are 1.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module Maj3 #(
    parameter WIDTH = 1
)(
    input  wire [WIDTH-1:0] in1,
    input  wire [WIDTH-1:0] in2,
    input  wire [WIDTH-1:0] in3,
    output wire [WIDTH-1:0] out
);

    assign out = (in1 & in2) | (in1 & in3) | (in2 & in3);

endmodule

/* One-hot Multiplexer, sel[k] selects input in<k>.
 *
 * @author    Igor Lesik
 * @copyright 2014 Igor Lesik, MIT License
 */

module Mux1hot3
#(
    parameter WIDTH = 1
)(
    input  wire [WIDTH-1:0] in0,
    input  wire [WIDTH-1:0] in1,
    input  wire [WIDTH-1:0] in2,
    input  wire [2:0]       sel,
    output wire [WIDTH-1:0] out
);

assign out = ({WIDTH{sel[0]}} & in0) | ({WIDTH{sel[1]}} & in1) | ({WIDTH{sel[2]}} & in2);

endmodule

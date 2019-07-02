/**@file
 * @brief     One-hot Multiplexer 
 * @author    Igor Lesik
 * @copyright Igor Lesik 2014
 *
 */

module Mux1hot3
#(
    parameter WIDTH = 1
)(
    input  wire [WIDTH-1:0] in1,
    input  wire [WIDTH-1:0] in2,
    input  wire [WIDTH-1:0] in3,
    input  wire [2:0]       sel,
    output wire [WIDTH-1:0] out
);

assign out = ({WIDTH{sel[0]}} & in1) | ({WIDTH{sel[1]}} & in2) | ({WIDTH{sel[2]}} & in3);

endmodule


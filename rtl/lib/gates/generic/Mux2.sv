/**@file
 * @brief     Multiplexer 
 * @author    Igor Lesik
 * @copyright Igor Lesik 2014
 *
 */

module Mux2 #(
    parameter WIDTH = 1
)(
    input  wire [WIDTH-1:0]  in1,
    input  wire [WIDTH-1:0]  in2,
    input  wire              sel,
    output wire [WIDTH-1:0]  out
);

assign out = (sel == 0) ? in1 : in2;

endmodule

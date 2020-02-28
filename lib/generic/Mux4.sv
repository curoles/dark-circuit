/**@file
 * @brief     Multiplexer 
 * @author    Igor Lesik
 * @copyright Igor Lesik 2014
 *
 */

module Mux4 #(
    parameter WIDTH = 1
)(
    input  wire [WIDTH-1:0]  in1,
    input  wire [WIDTH-1:0]  in2,
    input  wire [WIDTH-1:0]  in3,
    input  wire [WIDTH-1:0]  in4,
    input  wire [1:0]        sel,
    output wire [WIDTH-1:0]  out
);

assign out = (sel == 0) ? in1 :
             (sel == 1) ? in2 :
             (sel == 2) ? in3 : in4;

endmodule

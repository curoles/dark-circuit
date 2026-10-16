/**@file
 * @brief     Multiplexer 
 * @author    Igor Lesik
 * @copyright Igor Lesik 2014
 *
 */

module Mux3 #(
    parameter WIDTH = 1
)(
    input  wire [WIDTH-1:0]  in1,
    input  wire [WIDTH-1:0]  in2,
    input  wire [WIDTH-1:0]  in3,
    input  wire [1:0]        sel,
    output wire [WIDTH-1:0]  out
);

assign out = (sel == 0) ? in3 :
             (sel == 1) ? in2 : in1;

endmodule

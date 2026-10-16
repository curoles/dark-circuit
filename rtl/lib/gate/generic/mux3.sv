/**@file
 * @brief     Multiplexer, sel 0 selects in0, 1 selects in1, 2 and 3 select in2
 * @author    Igor Lesik
 * @copyright Igor Lesik 2014
 *
 */

module Mux3 #(
    parameter WIDTH = 1
)(
    input  wire [WIDTH-1:0]  in0,
    input  wire [WIDTH-1:0]  in1,
    input  wire [WIDTH-1:0]  in2,
    input  wire [1:0]        sel,
    output wire [WIDTH-1:0]  out
);

assign out = (sel == 0) ? in0 :
             (sel == 1) ? in1 : in2;

endmodule

/**@file
 * @brief     Comparator
 * @author    Igor Lesik
 * @copyright Igor Lesik 2014
 *
 */
module Cmp #(
    parameter WIDTH = 1
)(
    input  wire [WIDTH-1:0] in1,
    input  wire [WIDTH-1:0] in2,
    output wire             eq
);
   
assign eq = (in1 == in2);

endmodule

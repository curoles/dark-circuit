/* Comparator, returns 1 if in1 equals in2.
 *
 * Author:  Igor Lesik 2014
 *
 */
module CmpEQ #(
    parameter WIDTH = 1
)(
    input  wire [WIDTH-1:0] in1,
    input  wire [WIDTH-1:0] in2,
    output wire             eq
);
   
    assign eq = (in1 == in2);

endmodule

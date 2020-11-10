/* Comparator, returns 1 if in1 mismatches in2.
 *
 * Author:  Igor Lesik 2014
 *
 */
module CmpNE #(
    parameter WIDTH = 1
)(
    input  wire [WIDTH-1:0] in1,
    input  wire [WIDTH-1:0] in2,
    output wire             ne
);
   
    assign ne = |(in1 ^ in2);

endmodule

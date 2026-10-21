/* Comparator, returns 1 if in1 equals in2.
 *
 * @author    Igor Lesik
 * @copyright 2014 Igor Lesik, MIT License
 */
module CmpEq #(
    parameter WIDTH = 1
)(
    input  wire [WIDTH-1:0] in1,
    input  wire [WIDTH-1:0] in2,
    output wire             eq
);

    assign eq = (in1 == in2);

endmodule

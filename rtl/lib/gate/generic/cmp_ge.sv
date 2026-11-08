/* Comparator, returns 1 if in1 is greater than or equal to in2, both unsigned.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module CmpGe #(
    parameter WIDTH = 1
)(
    input  wire [WIDTH-1:0] in1,
    input  wire [WIDTH-1:0] in2,
    output wire             ge
);

    assign ge = (in1 >= in2);

endmodule

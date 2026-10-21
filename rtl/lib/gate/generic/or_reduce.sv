/* OR reduction, returns 1 if any bit of input is 1.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module OrReduce #(
    parameter WIDTH = 1
)(
    input  wire [WIDTH-1:0] in,
    output wire             out
);

    assign out = |in;

endmodule

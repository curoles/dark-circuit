/* AND reduction, returns 1 if all bits of input are 1.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module AndReduce #(
    parameter WIDTH = 1
)(
    input  wire [WIDTH-1:0] in,
    output wire             out
);

    assign out = &in;

endmodule

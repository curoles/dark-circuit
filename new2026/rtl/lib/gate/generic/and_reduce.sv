/* AND reduction, returns 1 if all bits of input are 1.
 *
 */
module AndReduce #(
    parameter WIDTH = 1
)(
    input  wire [WIDTH-1:0] in,
    output wire             out
);

    assign out = &in;

endmodule

/* OR reduction, returns 1 if any bit of input is 1.
 *
 */
module OrReduce #(
    parameter WIDTH = 1
)(
    input  wire [WIDTH-1:0] in,
    output wire             out
);

    assign out = |in;

endmodule

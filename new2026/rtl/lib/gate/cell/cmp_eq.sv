/* Comparator, returns 1 if in1 equals in2.
 *
 * Author:  Igor Lesik 2014
 *
 * Xnor2 per bit, then AndReduce.
 */
module CmpEq #(
    parameter WIDTH = 1
)(
    input  wire [WIDTH-1:0] in1,
    input  wire [WIDTH-1:0] in2,
    output wire             eq
);
    wire [WIDTH-1:0] bit_eq;

    Xnor2     #(WIDTH) u_xnor2     (.in1(in1), .in2(in2), .out(bit_eq));
    AndReduce #(WIDTH) u_and_reduce(.in(bit_eq), .out(eq));

endmodule

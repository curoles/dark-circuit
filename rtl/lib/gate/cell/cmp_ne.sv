/* Comparator, returns 1 if in1 mismatches in2.
 *
 * Xor2 per bit, then OrReduce.
 *
 * @author    Igor Lesik
 * @copyright 2014 Igor Lesik, MIT License
 */
module CmpNe #(
    parameter WIDTH = 1
)(
    input  wire [WIDTH-1:0] in1,
    input  wire [WIDTH-1:0] in2,
    output wire             ne
);
    wire [WIDTH-1:0] bit_ne;

    Xor2     #(WIDTH) u_xor2     (.in1(in1), .in2(in2), .out(bit_ne));
    OrReduce #(WIDTH) u_or_reduce(.in(bit_ne), .out(ne));

endmodule

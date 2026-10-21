/* Adder-comparator: eq = (a + b == c), mod 2^WIDTH, behavioral.
 *
 * a + b wraps around like a WIDTH-bit adder, its carry out is not compared.
 *
 * @author    Igor Lesik
 * @copyright 2019 Igor Lesik, MIT License
 */
module AddCmp #(
    parameter WIDTH = 32
)(
    input  wire [WIDTH-1:0] a,
    input  wire [WIDTH-1:0] b,
    input  wire [WIDTH-1:0] c,
    output wire             eq   // a + b == c
);
    wire [WIDTH-1:0] sum;

    assign sum = a + b;
    assign eq  = sum == c;

endmodule

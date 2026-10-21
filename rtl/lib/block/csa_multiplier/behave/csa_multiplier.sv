/* Carry-save array multiplier: product = a * b, unsigned, behavioral.
 *
 * Same ports and result as the struct version (array of carry-save adders).
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module CsaMultiplier #(
    parameter WIDTH = 32
)(
    input  wire [WIDTH-1:0]   a,
    input  wire [WIDTH-1:0]   b,
    output wire [2*WIDTH-1:0] product
);

    assign product = {{WIDTH{1'b0}}, a} * {{WIDTH{1'b0}}, b};

endmodule

/* Wallace tree multiplier: product = a * b, unsigned, behavioral.
 *
 * Same ports and result as the struct version (a Wallace tree of carry-save adders and a
 * Kogge-Stone adder); here the simulator multiplies.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module WallaceMultiplier #(
    parameter WIDTH = 32
)(
    input  wire [WIDTH-1:0]   a,
    input  wire [WIDTH-1:0]   b,
    output wire [2*WIDTH-1:0] product
);

    assign product = {{WIDTH{1'b0}}, a} * {{WIDTH{1'b0}}, b};

endmodule

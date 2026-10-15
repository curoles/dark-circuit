/* Inverter.
 *
 * Built bit by bit from cell INV.
 */
module Inv #(
    parameter WIDTH = 1
)(
    input  wire [WIDTH-1:0] in,  // to be inverted
    output wire [WIDTH-1:0] out  // out is inverted in
);

    genvar i;
    generate
    for (i = 0; i < WIDTH; i = i + 1) begin: g_bit
        INV u_inv(.I(in[i]), .ZN(out[i]));
    end
    endgenerate

endmodule

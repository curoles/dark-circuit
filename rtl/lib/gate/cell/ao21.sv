/* AND-OR, out = (in1 & in2) | in3.
 *
 * Built bit by bit from cells AOI21 and INV: the gate need not invert as the cell does.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module Ao21 #(
    parameter WIDTH = 1
)(
    input  wire [WIDTH-1:0] in1, // to be AND-ed with in2
    input  wire [WIDTH-1:0] in2, // to be AND-ed with in1
    input  wire [WIDTH-1:0] in3,
    output wire [WIDTH-1:0] out
);

    genvar i;
    generate
    for (i = 0; i < WIDTH; i = i + 1) begin: g_bit
        wire out_n;

        AOI21 u_aoi21(.A1(in1[i]), .A2(in2[i]), .B(in3[i]), .ZN(out_n));
        INV   u_inv(.I(out_n), .ZN(out[i]));
    end
    endgenerate

endmodule

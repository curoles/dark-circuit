/* 3-input NAND with 2 inverted inputs, out = ~(~in1 & ~in2 & in3).
 *
 * Built bit by bit from cell IIND3.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module Iind3 #(
    parameter WIDTH = 1
)(
    input  wire [WIDTH-1:0] in1, // inverted
    input  wire [WIDTH-1:0] in2, // inverted
    input  wire [WIDTH-1:0] in3,
    output wire [WIDTH-1:0] out
);

    genvar i;
    generate
    for (i = 0; i < WIDTH; i = i + 1) begin: g_bit
        IIND3 u_iind3(.A1(in1[i]), .A2(in2[i]), .B1(in3[i]), .ZN(out[i]));
    end
    endgenerate

endmodule

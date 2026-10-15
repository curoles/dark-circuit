/* 3-input NAND with 1 inverted input, out = ~(~in1 & in2 & in3).
 *
 * Built bit by bit from cell IND3.
 */
module Ind3 #(
    parameter WIDTH = 1
)(
    input  wire [WIDTH-1:0] in1, // inverted
    input  wire [WIDTH-1:0] in2,
    input  wire [WIDTH-1:0] in3,
    output wire [WIDTH-1:0] out
);

    genvar i;
    generate
    for (i = 0; i < WIDTH; i = i + 1) begin: g_bit
        IND3 u_ind3(.A1(in1[i]), .B1(in2[i]), .B2(in3[i]), .ZN(out[i]));
    end
    endgenerate

endmodule

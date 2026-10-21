/* 2-input NAND with 1 inverted input, out = ~(~in1 & in2).
 *
 * Built bit by bit from cell IND2.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module Ind2 #(
    parameter WIDTH = 1
)(
    input  wire [WIDTH-1:0] in1, // inverted
    input  wire [WIDTH-1:0] in2,
    output wire [WIDTH-1:0] out
);

    genvar i;
    generate
    for (i = 0; i < WIDTH; i = i + 1) begin: g_bit
        IND2 u_ind2(.A1(in1[i]), .B1(in2[i]), .ZN(out[i]));
    end
    endgenerate

endmodule

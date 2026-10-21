/* 3-input NAND.
 *
 * Built bit by bit from cell ND3.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module Nand3 #(
    parameter WIDTH = 1
)(
    input  wire [WIDTH-1:0] in1,
    input  wire [WIDTH-1:0] in2,
    input  wire [WIDTH-1:0] in3,
    output wire [WIDTH-1:0] out
);

    genvar i;
    generate
    for (i = 0; i < WIDTH; i = i + 1) begin: g_bit
        ND3 u_nd3(.A1(in1[i]), .A2(in2[i]), .A3(in3[i]), .ZN(out[i]));
    end
    endgenerate

endmodule

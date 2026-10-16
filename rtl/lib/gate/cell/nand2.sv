/* 2-input NAND.
 *
 * Built bit by bit from cell ND2.
 */
module Nand2 #(
    parameter WIDTH = 1
)(
    input  wire [WIDTH-1:0] in1,
    input  wire [WIDTH-1:0] in2,
    output wire [WIDTH-1:0] out
);

    genvar i;
    generate
    for (i = 0; i < WIDTH; i = i + 1) begin: g_bit
        ND2 u_nd2(.A1(in1[i]), .A2(in2[i]), .ZN(out[i]));
    end
    endgenerate

endmodule

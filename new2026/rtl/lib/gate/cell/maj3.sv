/* 3-input Majority, out bit is 1 when at least 2 of 3 input bits are 1.
 *
 * Built bit by bit from cell MAJ3.
 */
module Maj3 #(
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
        MAJ3 u_maj3(.A1(in1[i]), .A2(in2[i]), .A3(in3[i]), .Z(out[i]));
    end
    endgenerate

endmodule

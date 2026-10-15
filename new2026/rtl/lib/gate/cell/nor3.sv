/* 3-input NOR.
 *
 * Built bit by bit from cell NR3.
 */
module Nor3 #(
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
        NR3 u_nr3(.A1(in1[i]), .A2(in2[i]), .A3(in3[i]), .ZN(out[i]));
    end
    endgenerate

endmodule

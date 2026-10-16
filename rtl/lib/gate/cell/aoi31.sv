/* AND-OR-Invert, 3-Input AND Feeding NOR with 1 input.
 *
 * Built bit by bit from cell AOI31.
 */
module Aoi31 #(
    parameter WIDTH = 1
)(
    input  wire [WIDTH-1:0] in1,
    input  wire [WIDTH-1:0] in2,
    input  wire [WIDTH-1:0] in3,
    input  wire [WIDTH-1:0] in4,
    output wire [WIDTH-1:0] out
);

    genvar i;
    generate
    for (i = 0; i < WIDTH; i = i + 1) begin: g_bit
        AOI31 u_aoi31(.A1(in1[i]), .A2(in2[i]), .A3(in3[i]), .B(in4[i]), .ZN(out[i]));
    end
    endgenerate

endmodule

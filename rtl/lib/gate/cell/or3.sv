/* 3-input OR.
 *
 * Built bit by bit from cell OR3.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module Or3 #(
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
        OR3 u_or3(.A1(in1[i]), .A2(in2[i]), .A3(in3[i]), .Z(out[i]));
    end
    endgenerate

endmodule

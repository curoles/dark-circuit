/* OR-AND-Invert, out = ~((in1 | in2) & in3).
 *
 * Built bit by bit from cell OAI21.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module Oai21 #(
    parameter WIDTH = 1
)(
    input  wire [WIDTH-1:0] in1, // to be OR-ed with in2
    input  wire [WIDTH-1:0] in2, // to be OR-ed with in1
    input  wire [WIDTH-1:0] in3,
    output wire [WIDTH-1:0] out
);

    genvar i;
    generate
    for (i = 0; i < WIDTH; i = i + 1) begin: g_bit
        OAI21 u_oai21(.A1(in1[i]), .A2(in2[i]), .B(in3[i]), .ZN(out[i]));
    end
    endgenerate

endmodule

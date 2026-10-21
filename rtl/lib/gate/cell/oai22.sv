/* Complex gate OR-AND-Invertor.
 *
 * Built bit by bit from cell OAI22.
 *
 * <pre>
 *  in1 ----------+--\
 *                )OR +----+
 *  in2 ----------+--/|    |
 *                    |NAND|o----- out
 *  in3 ----------+--\|    |
 *                )OR +----+
 *  in4 ----------+--/
 * </pre>
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module Oai22 #(
    parameter WIDTH = 1
)(
    input  wire [WIDTH-1:0] in1, // to be OR-ed with in2
    input  wire [WIDTH-1:0] in2, // to be OR-ed with in1
    input  wire [WIDTH-1:0] in3, // to be OR-ed with in4
    input  wire [WIDTH-1:0] in4, // to be OR-ed with in3
    output wire [WIDTH-1:0] out  // NAND the results of two ORs
);

    genvar i;
    generate
    for (i = 0; i < WIDTH; i = i + 1) begin: g_bit
        OAI22 u_oai22(.A1(in1[i]), .A2(in2[i]), .B1(in3[i]), .B2(in4[i]), .ZN(out[i]));
    end
    endgenerate

endmodule

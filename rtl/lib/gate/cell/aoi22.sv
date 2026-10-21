/* Complex gate And-Or-Invertor.
 *
 * Built bit by bit from cell AOI22.
 *
 * <pre>
 *  in1 ----------+--\
 *                AND +----+
 *  in2 ----------+--/|    |
 *                    |NOR |o----- out
 *  in3 ----------+--\|    |
 *                AND +----+
 *  in4 ----------+--/
 * </pre>
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module Aoi22 #(
    parameter WIDTH = 1
)(
    input  wire [WIDTH-1:0] in1, // to be AND-ed with in2
    input  wire [WIDTH-1:0] in2, // to be AND-ed with in1
    input  wire [WIDTH-1:0] in3, // to be AND-ed with in4
    input  wire [WIDTH-1:0] in4, // to be AND-ed with in3
    output wire [WIDTH-1:0] out  // NOR the results of two ANDs
);

    genvar i;
    generate
    for (i = 0; i < WIDTH; i = i + 1) begin: g_bit
        AOI22 u_aoi22(.A1(in1[i]), .A2(in2[i]), .B1(in3[i]), .B2(in4[i]), .ZN(out[i]));
    end
    endgenerate

endmodule

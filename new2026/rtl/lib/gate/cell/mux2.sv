/* 2:1 Multiplexer.
 *
 * Built bit by bit from cell MUX2.
 *
 * <pre>
 *           +-----+
 * in1 ------| 1   |
 *           | MUX |--- out
 * in2 ------| 0   |
 *           +--+--+
 *         sel  |
 * </pre>
 */
module Mux2 #(
    parameter WIDTH = 1
)(
    input  wire [WIDTH-1:0]  in1,  // selected when sel is 1
    input  wire [WIDTH-1:0]  in2,  // selected when sel is 0
    input  wire              sel,
    output wire [WIDTH-1:0]  out
);

    genvar i;
    generate
    for (i = 0; i < WIDTH; i = i + 1) begin: g_bit
        MUX2 u_mux2(.I0(in2[i]), .I1(in1[i]), .S(sel), .Z(out[i]));
    end
    endgenerate

endmodule

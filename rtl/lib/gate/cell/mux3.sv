/* 3:1 Multiplexer, sel 0 selects in0, 1 selects in1, 2 and 3 select in2.
 *
 * Built bit by bit from cell MUX3.
 */
module Mux3 #(
    parameter WIDTH = 1
)(
    input  wire [WIDTH-1:0]  in0,
    input  wire [WIDTH-1:0]  in1,
    input  wire [WIDTH-1:0]  in2,
    input  wire [1:0]        sel,
    output wire [WIDTH-1:0]  out
);

    genvar i;
    generate
    for (i = 0; i < WIDTH; i = i + 1) begin: g_bit
        MUX3 u_mux3(.I0(in0[i]), .I1(in1[i]), .I2(in2[i]), .S0(sel[0]), .S1(sel[1]), .Z(out[i]));
    end
    endgenerate

endmodule

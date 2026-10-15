/* 4:1 Multiplexer, sel k selects input in<k>.
 *
 * Built bit by bit from cell MUX4.
 */
module Mux4 #(
    parameter WIDTH = 1
)(
    input  wire [WIDTH-1:0]  in0,
    input  wire [WIDTH-1:0]  in1,
    input  wire [WIDTH-1:0]  in2,
    input  wire [WIDTH-1:0]  in3,
    input  wire [1:0]        sel,
    output wire [WIDTH-1:0]  out
);

    genvar i;
    generate
    for (i = 0; i < WIDTH; i = i + 1) begin: g_bit
        MUX4 u_mux4(.I0(in0[i]), .I1(in1[i]), .I2(in2[i]), .I3(in3[i]), .S0(sel[0]), .S1(sel[1]), .Z(out[i]));
    end
    endgenerate

endmodule

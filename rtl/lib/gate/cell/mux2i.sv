/* Inverting 2:1 Multiplexer, out = ~(sel ? in1 : in0).
 *
 * Built bit by bit from cell MUX2N.
 */
module Mux2i #(
    parameter WIDTH = 1
)(
    input  wire [WIDTH-1:0] in0,  // inverted to out when sel is 0
    input  wire [WIDTH-1:0] in1,  // inverted to out when sel is 1
    input  wire             sel,
    output wire [WIDTH-1:0] out
);

    genvar i;
    generate
    for (i = 0; i < WIDTH; i = i + 1) begin: g_bit
        MUX2N u_mux2n(.I0(in0[i]), .I1(in1[i]), .S(sel), .ZN(out[i]));
    end
    endgenerate

endmodule

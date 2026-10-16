/* Booth Multiplexer.
 *
 * Built bit by bit from cell BML.
 */
module Bml #(
    parameter WIDTH = 1
)(
    input  wire [WIDTH-1:0] X2,
    input  wire [WIDTH-1:0] A,
    input  wire [WIDTH-1:0] S,
    input  wire [WIDTH-1:0] M0,
    input  wire [WIDTH-1:0] M1,
    output wire [WIDTH-1:0] PP
);

    genvar i;
    generate
    for (i = 0; i < WIDTH; i = i + 1) begin: g_bit
        BML u_bml(.X2(X2[i]), .A(A[i]), .S(S[i]), .M0(M0[i]), .M1(M1[i]), .PP(PP[i]));
    end
    endgenerate

endmodule

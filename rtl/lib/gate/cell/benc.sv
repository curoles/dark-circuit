/* Booth Encoding.
 *
 * Built bit by bit from cell BENC.
 *
 * The M2, M1, and M0 inputs are the three bits from the multiplier
 * that are used to derive the Partial Product.
 */
module Benc #(
    parameter WIDTH = 1
)(
    input  wire [WIDTH-1:0]  M0,
    input  wire [WIDTH-1:0]  M1,
    input  wire [WIDTH-1:0]  M2,
    output wire [WIDTH-1:0]  S,
    output wire [WIDTH-1:0]  A,
    output wire [WIDTH-1:0]  X2
);

    genvar i;
    generate
    for (i = 0; i < WIDTH; i = i + 1) begin: g_bit
        BENC u_benc(.M0(M0[i]), .M1(M1[i]), .M2(M2[i]), .S(S[i]), .A(A[i]), .X2(X2[i]));
    end
    endgenerate

endmodule

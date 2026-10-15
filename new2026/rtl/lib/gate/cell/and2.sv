/* 2-input AND.
 *
 * Built bit by bit from cell AN2.
 */
module And2 #(
    parameter WIDTH = 1
)(
    input  wire [WIDTH-1:0] in1,
    input  wire [WIDTH-1:0] in2,
    output wire [WIDTH-1:0] out
);

    genvar i;
    generate
    for (i = 0; i < WIDTH; i = i + 1) begin: g_bit
        AN2 u_an2(.A1(in1[i]), .A2(in2[i]), .Z(out[i]));
    end
    endgenerate

endmodule

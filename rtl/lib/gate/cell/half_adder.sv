/* Half Adder, independent for every bit.
 *
 * Built bit by bit from cell HA1.
 */
module HalfAdder #(
    parameter WIDTH = 1
)(
    input  wire [WIDTH-1:0] in1,
    input  wire [WIDTH-1:0] in2,
    output wire [WIDTH-1:0] sum,
    output wire [WIDTH-1:0] co   // carry out
);

    genvar i;
    generate
    for (i = 0; i < WIDTH; i = i + 1) begin: g_bit
        HA1 u_ha1(.A(in1[i]), .B(in2[i]), .S(sum[i]), .CO(co[i]));
    end
    endgenerate

endmodule

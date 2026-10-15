/* Full Adder, independent for every bit (no carry chain between bits).
 *
 * Built bit by bit from cell FA1.
 */
module FullAdder #(
    parameter WIDTH = 1
)(
    input  wire [WIDTH-1:0] in1,
    input  wire [WIDTH-1:0] in2,
    input  wire [WIDTH-1:0] ci,  // carry in
    output wire [WIDTH-1:0] sum,
    output wire [WIDTH-1:0] co   // carry out
);

    genvar i;
    generate
    for (i = 0; i < WIDTH; i = i + 1) begin: g_bit
        FA1 u_fa1(.A(in1[i]), .B(in2[i]), .CI(ci[i]), .S(sum[i]), .CO(co[i]));
    end
    endgenerate

endmodule

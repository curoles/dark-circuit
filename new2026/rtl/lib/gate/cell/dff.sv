/* Rising edge triggered D Flip Flop.
 *
 * Built bit by bit from cell DFQ.
 */
module Dff #(
    parameter WIDTH = 1
)(
    input  wire             clk,
    input  wire [WIDTH-1:0] in,
    output wire [WIDTH-1:0] out
);

    genvar i;
    generate
    for (i = 0; i < WIDTH; i = i + 1) begin: g_bit
        DFQ u_dfq(.D(in[i]), .CP(clk), .Q(out[i]));
    end
    endgenerate

endmodule

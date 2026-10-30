/* Rising edge triggered D Flip Flop.
 *
 * Built bit by bit from cell DFQ.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
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


/* Rising edge triggered D Flip Flop with Enable: en=1 takes in, en=0 holds.
 *
 * Mux2 selects in (en=1) or out (en=0) in front of Dff.
 */
module DffEn #(
    parameter WIDTH = 1
)(
    input  wire             clk,
    input  wire             en,
    input  wire [WIDTH-1:0] in,
    output wire [WIDTH-1:0] out
);
    wire [WIDTH-1:0] next;

    Mux2 #(WIDTH) u_mux2(.in0(out), .in1(in), .sel(en), .out(next));
    Dff  #(WIDTH) u_dff (.clk(clk), .in(next), .out(out));

endmodule

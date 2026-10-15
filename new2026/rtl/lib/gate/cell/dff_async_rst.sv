/* D type Flip Flop with asynchronous reset.
 *
 * Built bit by bit from cell DFCNQ that clears to 0;
 * bit with reset value 1 has inverters on DFCNQ input and output.
 */
module DffAsyncRst #(
    parameter WIDTH = 1,
    parameter [WIDTH-1:0] RST_VAL = {WIDTH{1'b0}}
)(
    input  wire             clk,
    input  wire             rst_n,
    input  wire [WIDTH-1:0] in,
    output wire [WIDTH-1:0] out
);

    genvar i;
    generate
    for (i = 0; i < WIDTH; i = i + 1) begin: g_bit
        if (RST_VAL[i]) begin: g_rst1
            wire d_n, q_n;
            INV   u_inv_d(.I(in[i]), .ZN(d_n));
            DFCNQ u_dfcnq(.D(d_n), .CP(clk), .CDN(rst_n), .Q(q_n));
            INV   u_inv_q(.I(q_n), .ZN(out[i]));
        end else begin: g_rst0
            DFCNQ u_dfcnq(.D(in[i]), .CP(clk), .CDN(rst_n), .Q(out[i]));
        end
    end
    endgenerate

endmodule

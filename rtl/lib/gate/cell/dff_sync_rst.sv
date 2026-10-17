/* D type Flip Flop with Synchronous Reset to RST_VAL.
 *
 * Author: Igor Lesik
 *
 * http://www.sunburst-design.com/papers/CummingsSNUG2003Boston_Resets.pdf
 *
 * Gate in front of Dff, bit by bit: And2 with rst_n for reset value 0,
 * Or2 with inverted rst_n for reset value 1.
 */
module DffSyncRst #(
    parameter WIDTH = 1,
    parameter [WIDTH-1:0] RST_VAL = {WIDTH{1'b0}}
)(
    input  wire             clk,
    input  wire             rst_n,
    input  wire [WIDTH-1:0] in,
    output wire [WIDTH-1:0] out
);
    wire [WIDTH-1:0] d;

    for (genvar i = 0; i < WIDTH; i++) begin: g_bit
        if (RST_VAL[i]) begin: g_rst1
            wire rst;
            Inv #(1) u_inv(.in(rst_n), .out(rst));
            Or2 #(1) u_or2(.in1(in[i]), .in2(rst), .out(d[i]));
        end else begin: g_rst0
            And2 #(1) u_and2(.in1(in[i]), .in2(rst_n), .out(d[i]));
        end
    end

    Dff #(WIDTH) u_dff(.clk(clk), .in(d), .out(out));

endmodule


/* D type Flip Flop with Synchronous Reset to RST_VAL and Enable.
 *
 * Author: Igor Lesik
 *
 * http://www.sunburst-design.com/papers/CummingsSNUG2003Boston_Resets.pdf
 *
 * Mux2 selects in (en=1) or out (en=0) in front of DffSyncRst.
 */
module DffSyncRstEn #(
    parameter WIDTH = 1,
    parameter [WIDTH-1:0] RST_VAL = {WIDTH{1'b0}}
)(
    input  wire             clk,
    input  wire             rst_n,
    input  wire             en,
    input  wire [WIDTH-1:0] in,
    output wire [WIDTH-1:0] out
);
    wire [WIDTH-1:0] next;

    Mux2 #(WIDTH) u_mux2(.in0(out), .in1(in), .sel(en), .out(next));
    DffSyncRst #(.WIDTH(WIDTH), .RST_VAL(RST_VAL)) u_dff_sync_rst(
        .clk(clk), .rst_n(rst_n), .in(next), .out(out));

endmodule

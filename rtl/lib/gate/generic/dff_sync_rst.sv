/* D type Flip Flop with Synchronous Reset to RST_VAL.
 *
 * Author: Igor Lesik
 *
 * http://www.sunburst-design.com/papers/CummingsSNUG2003Boston_Resets.pdf
 *
 */
module DffSyncRst #(
    parameter WIDTH = 1,
    parameter [WIDTH-1:0] RST_VAL = {WIDTH{1'b0}}
)(
    input  wire             clk,
    input  wire             rst_n,
    input  wire [WIDTH-1:0] in,
    output reg  [WIDTH-1:0] out
);

    always @(posedge clk)
        if (!rst_n)
            out[WIDTH-1:0] <= RST_VAL;
        else
            out[WIDTH-1:0] <= in[WIDTH-1:0];

endmodule


/* D type Flip Flop with Synchronous Reset to RST_VAL and Enable.
 *
 * Author: Igor Lesik
 *
 * http://www.sunburst-design.com/papers/CummingsSNUG2003Boston_Resets.pdf
 *
 */
module DffSyncRstEn #(
    parameter WIDTH = 1,
    parameter [WIDTH-1:0] RST_VAL = {WIDTH{1'b0}}
)(
    input  wire             clk,
    input  wire             rst_n,
    input  wire             en,
    input  wire [WIDTH-1:0] in,
    output reg  [WIDTH-1:0] out
);

`ifdef DARKC_FAST_DFF_SYNC_RST_EN
    // WARNING just an idea, need to test
    // WARNING: if en=X then rst_n does not reset FF (in simulation).
    // WARNING: resets to 0, ignores RST_VAL.
    wire [WIDTH-1:0] fin;
    Nand2#(WIDTH) u_mux(
        .in1( ~(out & {WIDTH{rst_n & ~en}}) ),
        .in2( ~(in  & {WIDTH{rst_n &  en}}) ),
        .out(fin)
    );
    Dff#(WIDTH) u_dff(.clk(clk), .in(fin), .out(out));
`else
    always @(posedge clk)
        if (!rst_n)
            out[WIDTH-1:0] <= RST_VAL;
        else if (en)
            out[WIDTH-1:0] <= in[WIDTH-1:0];
        else
            out[WIDTH-1:0] <= out[WIDTH-1:0];
`endif

endmodule

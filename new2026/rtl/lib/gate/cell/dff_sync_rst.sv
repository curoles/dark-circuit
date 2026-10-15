/* D type Flip Flop with Synchronous Reset.
 *
 * Author: Igor Lesik
 *
 * http://www.sunburst-design.com/papers/CummingsSNUG2003Boston_Resets.pdf
 *
 * And2 with rst_n in front of Dff.
 */
module DffSyncRst #(
    parameter WIDTH = 1
)(
    input  wire             clk,
    input  wire             rst_n,
    input  wire [WIDTH-1:0] in,
    output wire [WIDTH-1:0] out
);
    wire [WIDTH-1:0] d;

    And2 #(WIDTH) u_and2(.in1(in), .in2({WIDTH{rst_n}}), .out(d));
    Dff  #(WIDTH) u_dff (.clk(clk), .in(d), .out(out));

endmodule


/* D type Flip Flop with Synchronous Reset and Enable.
 *
 * Author: Igor Lesik
 *
 * http://www.sunburst-design.com/papers/CummingsSNUG2003Boston_Resets.pdf
 *
 * Mux2 selects in (en=1) or out (en=0), And2 with rst_n, then Dff.
 */
module DffSyncRstEn #(
    parameter WIDTH = 1
)(
    input  wire             clk,
    input  wire             rst_n,
    input  wire             en,
    input  wire [WIDTH-1:0] in,
    output wire [WIDTH-1:0] out
);
    wire [WIDTH-1:0] next, d;

    Mux2 #(WIDTH) u_mux2(.in0(out), .in1(in), .sel(en), .out(next));
    And2 #(WIDTH) u_and2(.in1(next), .in2({WIDTH{rst_n}}), .out(d));
    Dff  #(WIDTH) u_dff (.clk(clk), .in(d), .out(out));

endmodule

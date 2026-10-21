/* D type Flip Flop with asynchronous reset.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module DffAsyncRst #(
    parameter WIDTH = 1,
    parameter [WIDTH-1:0] RST_VAL = {WIDTH{1'b0}}
)(
    input  wire             clk,
    input  wire             rst_n,
    input  wire [WIDTH-1:0] in,
    output reg  [WIDTH-1:0] out
);


    always @(posedge clk or negedge rst_n)
        if (!rst_n)
            out[WIDTH-1:0] <= RST_VAL;
        else
            out[WIDTH-1:0] <= in[WIDTH-1:0];

endmodule

/* D type Flip Flop with asynchronous reset and Enable.
 *
 */
module DffAsyncRstEn #(
    parameter WIDTH = 1,
    parameter [WIDTH-1:0] RST_VAL = {WIDTH{1'b0}}
)(
    input  wire             clk,
    input  wire             rst_n,
    input  wire             en,
    input  wire [WIDTH-1:0] in,
    output reg  [WIDTH-1:0] out
);


    always @(posedge clk or negedge rst_n)
        if (!rst_n)
            out[WIDTH-1:0] <= RST_VAL;
        else if (en)
            out[WIDTH-1:0] <= in[WIDTH-1:0];
        else
            out[WIDTH-1:0] <= out[WIDTH-1:0];

endmodule

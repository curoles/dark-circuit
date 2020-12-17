/* D type Flip Flop with asynchronous reset.
 *
 * Author: Igor Lesik
 *
 */
module DffAsyncRst #(
    parameter WIDTH = 1,
    parameter RST_VAL = WIDTH'b0
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
 * Author: Igor Lesik
 *
 */
module DffAsyncRstEn #(
    parameter WIDTH = 1,
    parameter RST_VAL = WIDTH'b0
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

/**@file
 * @brief     D type Flip Flop with asynchronous reset
 * @author    Igor Lesik
 * @copyright Igor Lesik 2014
 *
 */



//D type flip flop with asynchronous reset
//
module DffAsyncRst #(
    parameter WIDTH = 1,
    parameter RST_VAL = 'h0
)(
    input  wire             clk,
    input  wire             rst,
    input  wire [WIDTH-1:0] in,
    output reg  [WIDTH-1:0] out
);

wire rst_n;
assign rst_n = ~rst;

always @(posedge clk or posedge rst_n)
    if (rst)
        out[WIDTH-1:0] <= RST_VAL;
    else
        out[WIDTH-1:0] <= in[WIDTH-1:0];

endmodule

/* Rising edge triggered D Flip Flop.
 *
 * @author    Igor Lesik
 * @copyright 2014 Igor Lesik, MIT License
 */

module Dff #(
    parameter WIDTH = 1
)(
    input  wire             clk,
    input  wire [WIDTH-1:0] in,
    output reg  [WIDTH-1:0] out
);

    always_ff @(posedge clk)
        out[WIDTH-1:0] <= in[WIDTH-1:0];

`ifdef DFF_RANDOMIZE_INITIAL_VALUE
    initial begin
        out = $urandom_range(2**WIDTH - 1, 0);
    end
`endif

endmodule


/* Rising edge triggered D Flip Flop with Enable: en=1 takes in, en=0 holds.
 */
module DffEn #(
    parameter WIDTH = 1
)(
    input  wire             clk,
    input  wire             en,
    input  wire [WIDTH-1:0] in,
    output reg  [WIDTH-1:0] out
);

    always_ff @(posedge clk)
        if (en)
            out[WIDTH-1:0] <= in[WIDTH-1:0];

`ifdef DFF_RANDOMIZE_INITIAL_VALUE
    initial begin
        out = $urandom_range(2**WIDTH - 1, 0);
    end
`endif

endmodule

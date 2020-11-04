/**@file
 * @brief     Rising edge triggered D Flip Flop
 * @author    Igor Lesik
 * @copyright Igor Lesik 2014
 *
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

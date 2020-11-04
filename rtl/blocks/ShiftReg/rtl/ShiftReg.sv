/**
 * @file
 * @brief  Shift register
 * @author Igor Lesik 2020
 *
 *   parallel load
 *      +                           shift reg Nth bit
 *      |        mux                      ^
 *      |       +----+      +---------+   |
 *      |       |    |      |         |   |
 *      +-------+ 0  |      |  DFF    |   |
 *              |    |      |         |   |
 *              |    +------+         +---+--->
 *    +---------+ 1  |      |         |   to next
 *  prev stage  |    |      |         |   stage
 *  output      +-+--+      +---------+
 *                |
 *                + serial/parallel selector
 *  
 */

module ShiftReg #(
    parameter WIDTH = 8
)(
    input  wire             clk,
    input  wire             srl_prl,
    input  wire             srl_in,
    input  wire [WIDTH-1:0] prl_in,
    output wire             srl_out,
    output wire [WIDTH-1:0] prl_out
);

wire [WIDTH-1:0] ff_in;
wire [WIDTH-1:0] srls_in;

assign srl_out = prl_out[WIDTH-1];
assign srls_in[0] = srl_in;
assign srls_in[WIDTH-1:1] = prl_out[WIDTH-2:0];

Mux2#(.WIDTH(WIDTH)) mux_(
    .in1(prl_in),
    .in2(srls_in),
    .sel(srl_prl),
    .out(ff_in)
);

Dff#(.WIDTH(WIDTH)) ff_(
    .clk(clk),
    .in(ff_in),
    .out(prl_out)
);

endmodule: ShiftReg

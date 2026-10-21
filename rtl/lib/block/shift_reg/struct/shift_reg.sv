/* Shift register with parallel load, made of gates.
 *
 * On every rising edge: srl_prl=1 shifts toward MSB, srl_in goes into bit 0;
 * srl_prl=0 loads prl_in. srl_out is bit WIDTH-1.
 * WIDTH must be 2 or more.
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
 * @author    Igor Lesik
 * @copyright 2020 Igor Lesik, MIT License
 */
module ShiftReg #(
    parameter WIDTH = 8                 // 2 or more
)(
    input  wire             clk,
    input  wire             srl_prl,    // 1 shifts (serial), 0 loads prl_in (parallel)
    input  wire             srl_in,     // shifted into bit 0
    input  wire [WIDTH-1:0] prl_in,
    output wire             srl_out,    // bit WIDTH-1
    output wire [WIDTH-1:0] prl_out
);
    wire [WIDTH-1:0] shifted, ff_in;

    // Previous stage outputs, srl_in goes into bit 0.
    assign shifted = {prl_out[WIDTH-2:0], srl_in};

    Mux2 #(WIDTH) u_mux2(.in0(prl_in), .in1(shifted), .sel(srl_prl), .out(ff_in));
    Dff  #(WIDTH) u_dff (.clk(clk), .in(ff_in), .out(prl_out));

    assign srl_out = prl_out[WIDTH-1];

endmodule

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

endmodule: ShiftReg

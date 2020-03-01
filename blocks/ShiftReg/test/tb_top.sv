/* Shift register TB.
 * Author: Igor Lesik 2020
 *
 *
 *
 *
 */



/* Verilog TB top module.
 *
 * External C-TB drives the inputs and checks the outputs.
 */
module tb_top(
    input  wire          clk,
    input  wire          srl_prl,
    input  wire          srl_in,
    input  wire [32-1:0] prl_in,
    output wire          srl_out,
    output wire [32-1:0] prl_out
);

ShiftReg#(.WIDTH(32)) shift_reg_(
    .clk(clk),
    .srl_prl(srl_prl),
    .srl_in(srl_in),
    .prl_in(prl_in),
    .srl_out(srl_out),
    .prl_out(prl_out)
);

endmodule: tb_top

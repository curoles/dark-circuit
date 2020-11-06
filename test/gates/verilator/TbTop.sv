/* Verilog TB top module.
 *
 * Copyright Igor Lesik 2020.
 *
 * External C-TB drives the inputs and checks the outputs.
 */
module TbTop(
    input  wire          clk,
    input  wire [64-1:0] in1,
    output wire [64-1:0] out_inv
);

    INV#(64) inv_(.in(in1), .out(out_inv));

endmodule: TbTop

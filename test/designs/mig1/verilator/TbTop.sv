/* Verilog TB top module.
 *
 * Copyright Igor Lesik 2020.
 *
 * External C-TB drives the inputs and checks the outputs.
 */
module TbTop (
    input wire clk
);

    Mig1CPU cpu_(.clk(clk));

endmodule: TbTop

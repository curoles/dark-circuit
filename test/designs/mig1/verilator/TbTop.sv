/* Verilog TB top module.
 *
 * Copyright Igor Lesik 2020.
 *
 * External C-TB drives the inputs and checks the outputs.
 */
module TbTop (
    input wire clk,
    input wire rst,
    input wire [15:0] rst_addr
);

    Mig1CPU
        cpu_(
            .clk(clk),
            .rst(rst),
            .rst_addr(rst_addr[15:2])
    );

endmodule: TbTop

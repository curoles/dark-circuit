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
    // JTAG signals:
    wire tck, tms, tdi, tdo, trstn;

    // JTAG signals driven by external OpenOCD process via Remote Bitbanging
    SimDpiJtag#(.TCK_PERIOD(10), .ALWAYS_ENABLE(1), .TCP_PORT(9999))
        jtag_(
            .clk,
            .rst,
            .tck,
            .tms,
            .tdi,
            .trstn,
            .tdo
    );

    Mig1CPU
        cpu_(
            .clk(clk),
            .rst(rst),
            .rst_addr(rst_addr[15:2]),
            .tck,
            .tms,
            .tdi,
            .tdo,
            .trst(~trstn)
    );

endmodule: TbTop

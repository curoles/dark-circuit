/* Connect JTAG debugger/probe as an external DPI module.
 *
 * Author: Igor Lesik 2021
 *
 */


/* SV calls this function to let an external module acting as JTAG probe
 * to drive JTAG pins and read TDO (Test Data Output).
 */
import "DPI-C" function
int dpi_jtag_tick
(
    output bit tck,
    output bit tms,
    output bit tdi,
    output bit trstn,
    input  bit tdo
);

import "DPI-C" function
void dpi_jtag_create
(
    input int unsigned port
);

/* Connect JTAG debugger/probe as an external DPI module.
 *
 * Author: Igor Lesik 2021
 *
 * This module calls DPI function `dpi_jtag_tick`.
 * This module represents JTAG pins connected to an external
 * JTAG debugger/probe.
 *
 * To enable DPI JTAG simulation dynamically:
 *
 * - instantiate with `.ALWAYS_ENABLE(0)`
 * - in sim CL set `jtag_dpi_enable=1|0`
 *
 */
module SimDpiJtag #(
    parameter TCK_PERIOD = 10, // relative to `clk` signal
    parameter ALWAYS_ENABLE = 1,
    parameter TCP_PORT = 4444
)(
    input  wire   clk,
    input  wire   rst,
    output reg    tck,
    output reg    tms,
    output reg    tdi,
    output reg    trstn,
    input  wire   tdo
);

	longint unsigned tcp_port;
	longint unsigned tick_counter;
	reg enable;

	initial begin
        if (ALWAYS_ENABLE)
            enable = 1;
		else if (!$value$plusargs("jtag_dpi_enable=%d", enable))
			enable = 0;

        if (enable) begin
            tcp_port = TCP_PORT;
            void'($value$plusargs("jtag_dpi_tcp_port=%d", tcp_port));
            dpi_jtag_create(tcp_port);
        end
	end

	always @(posedge clk) begin
		if (rst) begin
			tick_counter = 0;
		end else begin
			if (enable && ((tick_counter % TCK_PERIOD) == 0)) begin
				void'(dpi_jtag_tick(tck, tms, tdi, trstn, tdo));
			end
			tick_counter = tick_counter + 1;
		end
	end

endmodule

`ifdef SIMDPIJTAGTESTTOP
module SimDpiJtagTestTop();

    reg clk, rst;
    reg tck, tms, tdi, tdo, trstn;

    initial begin
        clk = 0;
        forever begin
            #1;
            clk = ~clk;
        end
    end

    initial begin
        rst = 1;
        #5;
        rst = 0;
    end

    SimDpiJtag#(.TCK_PERIOD(10), .ALWAYS_ENABLE(1), .TCP_PORT(4444))
        _jtag(
            .clk(), .rst(),
            .tck(), .tms(), .tdi(), .tdo(), .trstn()
    );

endmodule
`endif
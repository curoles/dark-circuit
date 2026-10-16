/* Verilog TB top module.
 *
 * Copyright Igor Lesik 2020.
 *
 * External C-TB drives the inputs and checks the outputs.
 */
module TbTop(
    input string filename,
    input wire clk,
    input wire [4-1:0] addr,
    output reg [32-1:0] data
);

    SimROM#(.DATA_SIZE(4), .ADDR_WIDTH(4))
        rom_(.clk(clk), .addr(addr), .data(data));

    initial begin
        //$display("SimROM TbTop: load file %s", filename);
        //rom_.load(filename, rom_.VLOG_HEX_FORMAT);
        rom_.rom[0] = 0;
        rom_.rom[1] = 1;
        rom_.rom[2] = 2;
        rom_.rom[3] = 3;
    end

endmodule: TbTop

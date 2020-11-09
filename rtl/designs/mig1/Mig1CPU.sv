/* Mig1 CPU.
 *
 * Author: Igor Lesik 2020
 * Copyright: Igor Lesik 2020
 *
 */
module Mig1CPU #(
    localparam  DATA_SIZE  = 4, // Mig1 word size is 32 bits
    localparam  DATA_WIDTH = DATA_SIZE * 8,
    localparam  ADDR_WIDTH = 8,
    localparam  MEM_SIZE   = 2**ADDR_WIDTH
)(
    input wire clk,
    input wire rst,
    input wire [ADDR_WIDTH-1:2] rst_addr
);

    wire                  ram_rd_en;
    wire [ADDR_WIDTH-1:0] ram_rd_addr;
    wire [DATA_WIDTH-1:0] ram_rd_data;
    wire                  ram_wr_en;
    wire [ADDR_WIDTH-1:0] ram_wr_addr;
    wire [DATA_WIDTH-1:0] ram_wr_data;

    SimRAM#(.DATA_SIZE(DATA_SIZE), .ADDR_WIDTH(ADDR_WIDTH))
        ram_(.clk(clk),
             .rd_en(ram_rd_en), .rd_addr(ram_rd_addr), .rd_data(ram_rd_data),
             .wr_en(ram_wr_en), .wr_addr(ram_wr_addr), .wr_data(ram_wr_data)
    );

    wire core2mem_fetch_en;
    wire [ADDR_WIDTH-1:0] core2mem_fetch_addr;

    assign ram_rd_en = core2mem_fetch_en;
    assign ram_rd_addr = core2mem_fetch_addr;

    Mig1Core#(.ADDR_WIDTH(ADDR_WIDTH))
        core_(
            .clk(clk),
            .rst(rst),
            .rst_addr(rst_addr),
            .insn_fetch_en(core2mem_fetch_en),
            .insn_fetch_addr(core2mem_fetch_addr)
    );

    export "DPI-C" function public_get_PC;
    function int unsigned public_get_PC();
        public_get_PC = core2mem_fetch_addr;
    endfunction

endmodule: Mig1CPU


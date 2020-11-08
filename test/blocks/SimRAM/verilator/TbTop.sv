/* Verilog TB top module.
 *
 * Copyright Igor Lesik 2020.
 *
 * External C-TB drives the inputs and checks the outputs.
 */
module TbTop #(
    localparam ADDR_WIDTH = 6,
    localparam DATA_SIZE  = 4,
    localparam DATA_WIDTH = 8*DATA_SIZE
)(
    input wire                  clk,
    input wire                  rd_en,
    input wire [ADDR_WIDTH-1:0] rd_addr,
    output reg [DATA_WIDTH-1:0] rd_data,
    input wire                  wr_en,
    input wire [ADDR_WIDTH-1:0] wr_addr,
    input wire [DATA_WIDTH-1:0] wr_data
);

    SimRAM#(.DATA_SIZE(DATA_SIZE), .ADDR_WIDTH(ADDR_WIDTH))
        ram_(.clk(clk),
             .rd_en(rd_en), .rd_addr(rd_addr), .rd_data(rd_data),
             .wr_en(wr_en), .wr_addr(wr_addr), .wr_data(wr_data)
    );

endmodule: TbTop

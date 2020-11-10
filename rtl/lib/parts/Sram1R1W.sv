module Sram1R1W #(
    parameter ADDR_WIDTH,
    parameter DATA_WIDTH
)(
    input  wire                  clk,
    input  wire                  rd_en,
    input  wire                  wr_en,
    input  wire [ADDR_WIDTH-1:0] rd_addr,
    input  wire [ADDR_WIDTH-1:0] wr_addr,
    input  wire [DATA_WIDTH-1:0] data_in,
    output reg  [DATA_WIDTH-1:0] data_out
);

    localparam WL_NUM = 2**ADDR_WIDTH;

    wire [WL_NUM-1:0] rd_wordline;

    Decoder#(ADDR_WIDTH) rd_one_hot(.in(rd_addr), .out(rd_wordline));

    //TODO finish
endmodule

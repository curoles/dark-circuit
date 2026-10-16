`include "clog2.svh"

/* Verilog simulation RAM model.
 *
 * Author: Igor Lesik 2013-2021
 *
 */
module SimRAM #(
    parameter  DATA_SIZE  = 1, // 1-byte, 2-16bits, 4-32bits word
    localparam DATA_WIDTH = 8 * DATA_SIZE,
    localparam ADDR_START = `CLOG2(DATA_SIZE),
    parameter  ADDR_WIDTH = 8,
    parameter  MEM_SIZE   = 2**ADDR_WIDTH
)(
    input  wire                           clk,
    input  wire                           rd_en,
    input  wire [ADDR_WIDTH-1:ADDR_START] rd_addr,
    input  wire                           wr_en,
    input  wire [ADDR_WIDTH-1:ADDR_START] wr_addr,
    input  wire [DATA_WIDTH-1:0]          wr_data,
    output reg  [DATA_WIDTH-1:0]          rd_data,
    output reg                            rd_valid,
    input  wire [ADDR_WIDTH-1:ADDR_START] rd_addr_out
);

    // `objcopy -O verilog` uses byte address `@addr` regardless
    // of data width; let's treat memory as array of bytes, but
    // access by RAM bank size `DATA_SIZE`.
    reg [8-1:0] ram [MEM_SIZE];

    localparam VLOG_HEX_FORMAT = 0;
    localparam VLOG_BIN_FORMAT = 1;

    // Load memory contents from a file.
    //
    function int load(string filename, int format);
        if (format == VLOG_HEX_FORMAT)
            $readmemh(filename, ram);
        else if (format == VLOG_BIN_FORMAT)
            $readmemb(filename, ram);
        else
            return 0;

        return 1;
    endfunction


    function [DATA_WIDTH-1:0] read_bank(int addr);
        if (DATA_SIZE == 1)
            read_bank = ram[addr];
        else if (DATA_SIZE == 2)
            read_bank = {ram[addr+1],ram[addr]};
        else if (DATA_SIZE == 4)
            read_bank = {ram[addr+3],ram[addr+2],ram[addr+1],ram[addr]};

        //$display("Read bank addr=%h data=%h size=%d", addr, read_bank, DATA_SIZE);
    endfunction

    always @ (posedge clk)
    begin
        if (wr_en) begin
            ram[integer'(wr_addr)] <= wr_data;
        end

        if (rd_en) begin
            //$display("ROM[%h]=%h", /*integer'(rd_addr)*/{rd_addr,2'b00}, rd_data/*ram[integer'(rd_addr)]*/);
            rd_data <= read_bank(integer'(rd_addr) << ADDR_START);
            if (wr_en && rd_addr == wr_addr) begin
                assert(0);//FIXME
            end
        end

        rd_valid <= rd_en;
    end

endmodule: SimRAM


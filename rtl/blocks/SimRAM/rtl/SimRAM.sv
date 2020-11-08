/* Verilog simulation RAM model.
 *
 * Author: Igor Lesik 2013-2020
 *
 */
module SimRAM #(
    parameter  DATA_SIZE  = 1, // 1-byte, 2-16bits, 4-32bits word
    localparam DATA_WIDTH = 8 * DATA_SIZE,
    parameter  ADDR_WIDTH = 8,
    parameter  MEM_SIZE   = 2**ADDR_WIDTH
)(
    input  wire                  clk,
    input  wire                  rd_en,
    input  wire [ADDR_WIDTH-1:0] rd_addr,
    input  wire                  wr_en,
    input  wire [ADDR_WIDTH-1:0] wr_addr,
    input  wire [DATA_WIDTH-1:0] wr_data,
    output reg  [DATA_WIDTH-1:0] rd_data
);

    reg [DATA_WIDTH-1:0] ram [MEM_SIZE];

    localparam VLOG_HEX_FORMAT = 0;
    localparam VLOG_BIN_FORMAT = 1;
    //TODO localparam SREC_FORMAT = 2;

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


    always @ (posedge clk)
    begin
        if (wr_en) begin
            ram[integer'(wr_addr)] <= wr_data;
        end

        if (rd_en) begin
            //$display("ROM[%h]=%h", integer'(addr)+i, rom[integer'(addr)+i]);
            rd_data <= ram[integer'(rd_addr)];
            if (wr_en && rd_addr == wr_addr) begin
                assert(0);//FIXME
            end
        end
    end

endmodule: SimRAM


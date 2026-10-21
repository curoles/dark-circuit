/* Verilog simulation RAM model.
 *
 * Memory is array of bytes, because `objcopy -O verilog` uses byte address
 * @addr regardless of data width. Access is by word of DATA_SIZE bytes,
 * little-endian. Address ports are word addresses: bits ADDR_WIDTH-1..ADDR_START
 * of byte address, connect them as addr[ADDR_WIDTH-1:ADDR_START].
 *
 * Write: on rising edge, wr_en=1 writes bytes of wr_data with wr_strb=1 into word
 * at wr_addr: byte i of the word is wr_data[8*i +: 8] and it is written when
 * wr_strb[i] is 1. Use all ones to write the whole word.
 * Read: on rising edge, rd_en=1 reads word at rd_addr into rd_data;
 * rd_valid is rd_en delayed by 1 cycle.
 * Read and write of the same word in the same cycle reads old data.
 * Use peek() to read a byte directly, without clock.
 *
 * @author    Igor Lesik
 * @copyright 2013-2021 Igor Lesik, MIT License
 */
module SimRAM #(
    parameter  DATA_SIZE  = 1,                  // bytes in word: 1, 2, 4, 8, ...
    parameter  ADDR_WIDTH = 8,                  // byte address width
    parameter  MEM_SIZE   = 1 << ADDR_WIDTH,    // bytes
    localparam DATA_WIDTH = 8 * DATA_SIZE,
    localparam ADDR_START = $clog2(DATA_SIZE)   // word address starts at this bit of byte address
)(
    input  wire                           clk,
    input  wire                           rd_en,
    input  wire [ADDR_WIDTH-1:ADDR_START] rd_addr,  // word address
    input  wire                           wr_en,
    input  wire [ADDR_WIDTH-1:ADDR_START] wr_addr,  // word address
    input  wire [DATA_WIDTH-1:0]          wr_data,
    input  wire [DATA_SIZE-1:0]           wr_strb,  // byte i is written when wr_strb[i] is 1
    output reg  [DATA_WIDTH-1:0]          rd_data,
    output reg                            rd_valid
);
    reg [8-1:0] ram [MEM_SIZE];

    localparam VLOG_HEX_FORMAT = 0;
    localparam VLOG_BIN_FORMAT = 1;

    // Load memory contents from file, returns 0 if format is unknown.
    //
    // Verilog hex format example (byte address and bytes):
    // @0
    // 11
    // 22
    function automatic int load(string filename, int format);
        if (format == VLOG_HEX_FORMAT)
            $readmemh(filename, ram);
        else if (format == VLOG_BIN_FORMAT)
            $readmemb(filename, ram);
        else
            return 0;

        return 1;
    endfunction

    // Read byte at byte_addr directly, without clock and ports:
    // for testbenches and simulation models (debugger, semihosting).
    // Does not change the memory and does not disturb rd_data.
    function automatic logic [7:0] peek(input logic [ADDR_WIDTH-1:0] byte_addr);
        return ram[byte_addr];
    endfunction

    // Byte address of the first byte of the word.
    wire [ADDR_WIDTH-1:0] rd_base;
    wire [ADDR_WIDTH-1:0] wr_base;
    assign rd_base[ADDR_WIDTH-1:ADDR_START] = rd_addr;
    assign wr_base[ADDR_WIDTH-1:ADDR_START] = wr_addr;
    generate
    if (ADDR_START > 0) begin: g_base_low
        assign rd_base[ADDR_START-1:0] = {ADDR_START{1'b0}};
        assign wr_base[ADDR_START-1:0] = {ADDR_START{1'b0}};
    end
    endgenerate

    always_ff @(posedge clk) begin
        for (int i = 0; i < DATA_SIZE; i = i + 1) begin
            // Byte i of the word, address width matches ram index.
            if (rd_en)
                rd_data[8*i +: 8] <= ram[rd_base + i[ADDR_WIDTH-1:0]];
            if (wr_en && wr_strb[i])
                ram[wr_base + i[ADDR_WIDTH-1:0]] <= wr_data[8*i +: 8];
        end
        rd_valid <= rd_en;
    end

endmodule

/* Verilog simulation ROM model.
 *
 * Author: Igor Lesik 2013-2020
 *
 * Wrapper around SimRAM with write port disabled, so memory layout and
 * file format are the same as SimRAM: memory is array of bytes, access is
 * by word of DATA_SIZE bytes, little-endian. Address port is word address:
 * bits ADDR_WIDTH-1..ADDR_START of byte address, connect it as
 * addr[ADDR_WIDTH-1:ADDR_START]. On rising edge with en=1
 * data gets word at addr; data holds while en=0.
 *
 * Use load() to fill the ROM, addresses in file are byte addresses
 * like in output of `objcopy -O verilog`.
 *
 * Verilog binary format example:
 * <pre>
 * @003
 * 00000011
 * 00000100
 * @005
 * 00000101
 * </pre>
 *
 * Verilog hex format example:
 * <pre>
 * @003
 * 3
 * 4
 * </pre>
 */
module SimROM #(
    parameter  DATA_SIZE  = 1,                  // bytes in word: 1, 2, 4, 8, ...
    parameter  ADDR_WIDTH = 8,                  // byte address width
    parameter  MEM_SIZE   = 1 << ADDR_WIDTH,    // bytes
    localparam DATA_WIDTH = 8 * DATA_SIZE,
    localparam ADDR_START = $clog2(DATA_SIZE)   // word address starts at this bit of byte address
)(
    input  wire                           clk,
    input  wire                           en,    // 1: read word at addr on rising edge, 0: data holds
    input  wire [ADDR_WIDTH-1:ADDR_START] addr,  // word address
    output wire [DATA_WIDTH-1:0]          data   // word at addr, 1 clock after addr with en=1
);

    // rd_valid of SimRAM is en delayed by 1 clock, users who need it can delay en.
    /* verilator lint_off UNUSEDSIGNAL */
    wire rd_valid;
    /* verilator lint_on UNUSEDSIGNAL */

    SimRAM #(.DATA_SIZE(DATA_SIZE), .ADDR_WIDTH(ADDR_WIDTH), .MEM_SIZE(MEM_SIZE)) u_sim_ram(
        .clk(clk),
        .rd_en(en), .rd_addr(addr),
        .wr_en(1'b0), .wr_addr({(ADDR_WIDTH-ADDR_START){1'b0}}), .wr_data({DATA_WIDTH{1'b0}}),
        .wr_strb({DATA_SIZE{1'b0}}),
        .rd_data(data), .rd_valid(rd_valid));

    // Formats of load(), for callers: u_sim_rom.load(file, u_sim_rom.VLOG_HEX_FORMAT).
    /* verilator lint_off UNUSEDPARAM */
    localparam VLOG_HEX_FORMAT = 0;
    localparam VLOG_BIN_FORMAT = 1;
    /* verilator lint_on UNUSEDPARAM */

    // Load memory contents from file, returns 0 if format is unknown.
    function int load(string filename, int format);
        return u_sim_ram.load(filename, format);
    endfunction

    // Read byte at byte_addr directly, see SimRAM peek().
    function logic [7:0] peek(input logic [ADDR_WIDTH-1:0] byte_addr);
        return u_sim_ram.peek(byte_addr);
    endfunction

endmodule

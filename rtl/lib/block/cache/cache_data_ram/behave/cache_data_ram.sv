/* Data of a cache, one line per set, behavioral.
 *
 * A line is 1 << SETS_OFFSET bytes (DATA_WIDTH bits): the bytes of the address below the set
 * index. Read is synchronous: on rising edge, rd_en=1 reads the line of rd_set into data,
 * which holds while rd_en=0. Write: on rising edge, wr_en=1 writes wr_data into the line of
 * wr_set. A read and a write of the same set in the same cycle read the old line. Content
 * is unknown until written.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module CacheDataRam #(
    parameter  SETS_WIDTH  = 6,             // 1 << SETS_WIDTH sets
    parameter  SETS_OFFSET = 2,             // 1 << SETS_OFFSET bytes in a line
    localparam DATA_WIDTH  = 8 << SETS_OFFSET
)(
    input  wire                  clk,

    input  wire                  rd_en,
    input  wire [SETS_WIDTH-1:0] rd_set,
    output wire [DATA_WIDTH-1:0] data,          // line of rd_set, 1 clock after rd_en

    input  wire                  wr_en,
    input  wire [SETS_WIDTH-1:0] wr_set,
    input  wire [DATA_WIDTH-1:0] wr_data
);
    Sram1R1W #(.ADDR_WIDTH(SETS_WIDTH), .DATA_WIDTH(DATA_WIDTH)) u_sram_1r1w(
        .clk, .rd_en, .rd_addr(rd_set), .data_out(data),
        .wr_en, .wr_addr(wr_set), .data_in(wr_data));

endmodule

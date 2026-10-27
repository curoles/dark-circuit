/* Tags of a cache, one per set, behavioral.
 *
 * The tag is the part of the address above the set index and the offset in the line: it
 * tells which of the addresses that share a set the line holds. Read is synchronous: on
 * rising edge, rd_en=1 reads the tag of rd_set into tag, which holds while rd_en=0.
 * Write: on rising edge, wr_en=1 writes wr_tag into wr_set. A read and a write of the same
 * set in the same cycle read the old tag. Content is unknown until written (the valid bits
 * say which tags mean something).
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module CacheTagRam #(
    parameter SETS_WIDTH = 6,               // 1 << SETS_WIDTH sets
    parameter TAG_WIDTH  = 24
)(
    input  wire                  clk,

    input  wire                  rd_en,
    input  wire [SETS_WIDTH-1:0] rd_set,
    output wire [TAG_WIDTH-1:0]  tag,           // tag of rd_set, 1 clock after rd_en

    input  wire                  wr_en,
    input  wire [SETS_WIDTH-1:0] wr_set,
    input  wire [TAG_WIDTH-1:0]  wr_tag
);
    Sram1R1W #(.ADDR_WIDTH(SETS_WIDTH), .DATA_WIDTH(TAG_WIDTH)) u_sram_1r1w(
        .clk, .rd_en, .rd_addr(rd_set), .data_out(tag),
        .wr_en, .wr_addr(wr_set), .data_in(wr_tag));

endmodule

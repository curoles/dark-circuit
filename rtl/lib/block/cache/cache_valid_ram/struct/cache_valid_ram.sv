/* Valid bits of a cache, one per set, made of blocks and gates.
 *
 * Same ports and behavior as the behave version (see there): synchronous read, write of one
 * bit, reset and invalidate clear every bit.
 *
 * Every bit is a DffSyncRstEn: it takes wr_val when the write word line of its set is 1
 * (Decoder of wr_set, enabled by wr_en), else holds. The reset of the flops is rst_n AND NOT
 * invalidate: both clear every bit, and so invalidate wins over a write of the same cycle.
 * Read as in Sram1R1W: AND of the bits with the read word lines, OR of all, then a DffEn
 * (rd_en) for valid.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module CacheValidRam #(
    parameter  SETS_WIDTH = 6,              // 1 << SETS_WIDTH sets
    localparam SETS_COUNT = 1 << SETS_WIDTH
)(
    input  wire                  clk,
    input  wire                  rst_n,         // synchronous reset, active low: all invalid
    input  wire                  invalidate,    // all invalid, e.g. FENCE.I for an I-cache

    input  wire                  rd_en,
    input  wire [SETS_WIDTH-1:0] rd_set,
    output wire                  valid,         // bit of rd_set, 1 clock after rd_en

    input  wire                  wr_en,
    input  wire [SETS_WIDTH-1:0] wr_set,
    input  wire                  wr_val
);
    wire [SETS_COUNT-1:0] valid_mem;        // bit k: set k
    wire [SETS_COUNT-1:0] wr_line;          // one-hot: the set written
    wire [SETS_COUNT-1:0] rd_line;          // one-hot: the set read
    wire [SETS_COUNT-1:0] selected;
    wire                  invalidate_n;
    wire                  clear_n;          // 0: clear every bit
    wire                  read_val;

    Inv  #(1) u_inv (.in(invalidate), .out(invalidate_n));
    And2 #(1) u_and2(.in1(rst_n), .in2(invalidate_n), .out(clear_n));
    Decoder #(.SIZE(SETS_WIDTH)) u_decoder_wr(.in(wr_set), .en(wr_en), .out(wr_line));
    for (genvar k = 0; k < SETS_COUNT; k++) begin: g_set
        DffSyncRstEn #(.WIDTH(1)) u_dff_sync_rst_en(.clk(clk), .rst_n(clear_n), .en(wr_line[k]),
                                                    .in(wr_val), .out(valid_mem[k]));
    end

    Decoder  #(.SIZE(SETS_WIDTH)) u_decoder_rd(.in(rd_set), .en(1'b1), .out(rd_line));
    And2     #(SETS_COUNT) u_and2_rd(.in1(valid_mem), .in2(rd_line), .out(selected));
    OrReduce #(SETS_COUNT) u_or_reduce(.in(selected), .out(read_val));
    DffEn    #(1) u_dff_en_rd(.clk(clk), .en(rd_en), .in(read_val), .out(valid));

endmodule

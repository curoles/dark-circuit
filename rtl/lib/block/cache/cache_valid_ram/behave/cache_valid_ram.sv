/* Valid bits of a cache, one per set, behavioral.
 *
 * A cache keeps one valid bit per line: 0 while the line holds nothing. Read is synchronous
 * like the tag and data RAMs, so that the three answer together: on rising edge, rd_en=1
 * reads the bit of rd_set into valid, which holds while rd_en=0. Write: on rising edge,
 * wr_en=1 writes wr_val into the bit of wr_set. A read and a write of the same set in the
 * same cycle read the old bit. Reset and invalidate=1 clear every bit (invalidate wins over
 * a write of the same cycle): unlike tags and data, valid bits must start known.
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
    output logic                 valid,         // bit of rd_set, 1 clock after rd_en

    input  wire                  wr_en,
    input  wire [SETS_WIDTH-1:0] wr_set,
    input  wire                  wr_val
);
    logic [SETS_COUNT-1:0] valid_mem;

    always_ff @(posedge clk)
        if (!rst_n || invalidate) valid_mem         <= '0;
        else if (wr_en)           valid_mem[wr_set] <= wr_val;

    always_ff @(posedge clk)
        if (rd_en)
            valid <= valid_mem[rd_set];

endmodule

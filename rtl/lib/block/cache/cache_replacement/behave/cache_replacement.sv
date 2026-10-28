/* Replacement of a set-associative cache: which way of a set a fill replaces, behavioral.
 *
 * The cache reads the state of a set with each request (rd_en, rd_set, like its tag RAMs)
 * and, in the clock after, looks the request up: it gives the valid bits of the set's ways
 * (valid) and gets victim_way, the way a fill would replace: the highest invalid way when
 * one is invalid, else the way POLICY picks. touch=1 (a hit, or the fill of a miss, any clock
 * until the next read) tells which way of the set of the last read was used.
 *
 * POLICY (CachePkg):
 * - REPL_LRU: the least recently touched way. The state of every set (BitMatrixLru, WAYS *
 *   (WAYS - 1) / 2 bits) is in a RAM read with rd_en and written with every touch.
 *   Forwarding: a touch writes the RAM at the same rising edge as the next read; when that
 *   read is of the same set, it gets the old bits, so the bits written then are used instead
 *   (stale); the choice is exactly LRU also for back-to-back requests to one set.
 * - REPL_RANDOM: the low bits of an 8-bit Lfsr that steps every clock from reset (when the
 *   misses come mixes it); no state per set, rd_en, rd_set and touch are not used. WAYS must
 *   be a power of 2, at most 256.
 * The RAM needs no reset: invalid ways go first, see BitMatrixLru. WAYS is at least 2.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "dark_circuit_assert.svh"

module CacheReplacement import CachePkg::*; #(
    parameter  WAYS       = 4,                  // at least 2
    parameter  SETS_WIDTH = 6,                  // 1 << SETS_WIDTH sets
    parameter  POLICY     = REPL_LRU,           // CachePkg: REPL_LRU, REPL_RANDOM
    localparam WAY_WIDTH  = $clog2(WAYS)
)(
    input  wire                  clk,
    input  wire                  rst_n,         // synchronous reset, active low

    // Used by REPL_LRU only.
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire                  rd_en,         // with a request: read the state of rd_set
    input  wire [SETS_WIDTH-1:0] rd_set,
    input  wire                  touch,         // a hit or fill of touch_way, set of the last read
    input  wire [WAY_WIDTH-1:0]  touch_way,
    /* verilator lint_on UNUSEDSIGNAL */

    input  wire [WAYS-1:0]       valid,         // ways of the set of the last read holding a line
    output wire [WAY_WIDTH-1:0]  victim_way     // highest invalid way, else POLICY's way
);
    `DC_STATIC_ASSERT(a_ways_at_least_2, WAYS >= 2)
    `DC_STATIC_ASSERT(a_policy_known, POLICY == REPL_LRU || POLICY == REPL_RANDOM)

    if (POLICY == REPL_LRU) begin: g_lru
        localparam LRU_WIDTH = WAYS * (WAYS - 1) / 2;

        logic [SETS_WIDTH-1:0] set_q;       // set of the last read: touches are for it
        logic [LRU_WIDTH-1:0]  ram_bits;    // bits of set_q as the RAM read them
        logic [LRU_WIDTH-1:0]  wr_bits;     // bits of the last touch
        logic                  stale;       // a touch of set_q since its read: use wr_bits
        logic [LRU_WIDTH-1:0]  lru;         // bits of set_q now
        logic [LRU_WIDTH-1:0]  lru_next;

        Sram1R1W #(.ADDR_WIDTH(SETS_WIDTH), .DATA_WIDTH(LRU_WIDTH)) u_sram_1r1w(
            .clk, .rd_en, .rd_addr(rd_set), .data_out(ram_bits),
            .wr_en(touch), .wr_addr(set_q), .data_in(lru_next));

        always_ff @(posedge clk)
            if (rd_en)
                set_q <= rd_set;

        // A read gets bits a touch at the same edge does not change yet (the RAM reads the
        // old word): stale when that touch was of the same set; a touch later, while set_q
        // stays, makes the RAM's bits stale too.
        always_ff @(posedge clk)
            if (!rst_n)     stale <= 1'b0;
            else if (rd_en) stale <= touch && set_q == rd_set;
            else if (touch) stale <= 1'b1;

        always_ff @(posedge clk)
            if (touch)
                wr_bits <= lru_next;

        assign lru = stale ? wr_bits : ram_bits;

        BitMatrixLru #(.WAYS(WAYS)) u_bit_matrix_lru(
            .lru, .touch, .touch_way, .lru_next, .valid, .victim_way);
    end else if (POLICY == REPL_RANDOM) begin: g_random
        `DC_STATIC_ASSERT(a_random_ways_power_of_2, (WAYS & (WAYS - 1)) == 0)
        `DC_STATIC_ASSERT(a_random_ways_at_most_256, WAYS <= 256)

        // Only the low WAY_WIDTH bits are used.
        /* verilator lint_off UNUSEDSIGNAL */
        logic [7:0] q;
        /* verilator lint_on UNUSEDSIGNAL */

        Lfsr #(.WIDTH(8)) u_lfsr(.clk, .rst_n, .q);

        // Highest way that is not valid (as PriorityEncoder in the struct version); 0 when every
        // way is valid (not used then).
        function automatic [WAY_WIDTH-1:0] highest_invalid(input [WAYS-1:0] v);
            highest_invalid = '0;
            for (int w = 0; w < WAYS; w++)
                if (!v[w])
                    highest_invalid = WAY_WIDTH'(w);    // a higher way wins
        endfunction

        assign victim_way = (&valid) ? q[WAY_WIDTH-1:0] : highest_invalid(valid);
    end

endmodule

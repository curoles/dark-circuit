/* Replacement of a set-associative cache: which way of a set a fill replaces, made of blocks
 * and gates.
 *
 * Same ports and behavior as the behave version, see there (POLICY, forwarding).
 * REPL_LRU: the state RAM is the struct Sram1R1W; set_q and the bits of the last touch
 * (wr_bits) are DffEn (rd_en, touch); stale = DffSyncRst(rd_en ? touch AND (set_q ==
 * rd_set) : touch OR stale); lru = Mux2(ram_bits, wr_bits, stale) into BitMatrixLru.
 * REPL_RANDOM: the struct Lfsr; PriorityEncoder of the inverted valid bits gives the highest
 * invalid way, its valid output says some way is invalid, and Mux2 takes the Lfsr's low bits
 * otherwise.
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

        wire [SETS_WIDTH-1:0] set_q;        // set of the last read: touches are for it
        wire [LRU_WIDTH-1:0]  ram_bits;     // bits of set_q as the RAM read them
        wire [LRU_WIDTH-1:0]  wr_bits;      // bits of the last touch
        wire                  same_set;     // the new read is of set_q
        wire                  touch_same;   // a touch of set_q at the edge of its read
        wire                  touch_more;   // a touch while set_q stays, or stale already
        wire                  stale;        // a touch of set_q since its read: use wr_bits
        wire                  stale_next;
        wire [LRU_WIDTH-1:0]  lru;          // bits of set_q now
        wire [LRU_WIDTH-1:0]  lru_next;

        Sram1R1W #(.ADDR_WIDTH(SETS_WIDTH), .DATA_WIDTH(LRU_WIDTH)) u_sram_1r1w(
            .clk, .rd_en, .rd_addr(rd_set), .data_out(ram_bits),
            .wr_en(touch), .wr_addr(set_q), .data_in(lru_next));

        DffEn #(SETS_WIDTH) u_dff_en_set(.clk, .en(rd_en), .in(rd_set), .out(set_q));

        // stale: see the behave version for why.
        CmpEq #(SETS_WIDTH) u_cmp_eq_set(.in1(set_q), .in2(rd_set), .eq(same_set));
        And2  #(1) u_and2_same (.in1(touch), .in2(same_set), .out(touch_same));
        Or2   #(1) u_or2_more  (.in1(touch), .in2(stale), .out(touch_more));
        Mux2  #(1) u_mux2_stale(.in0(touch_more), .in1(touch_same), .sel(rd_en),
                                .out(stale_next));
        DffSyncRst #(.WIDTH(1)) u_dff_sync_rst_stale(.clk, .rst_n, .in(stale_next),
                                                     .out(stale));

        DffEn #(LRU_WIDTH) u_dff_en_wr_bits(.clk, .en(touch), .in(lru_next), .out(wr_bits));

        Mux2 #(LRU_WIDTH) u_mux2_lru(.in0(ram_bits), .in1(wr_bits), .sel(stale), .out(lru));

        BitMatrixLru #(.WAYS(WAYS)) u_bit_matrix_lru(
            .lru, .touch, .touch_way, .lru_next, .valid, .victim_way);
    end else if (POLICY == REPL_RANDOM) begin: g_random
        `DC_STATIC_ASSERT(a_random_ways_power_of_2, (WAYS & (WAYS - 1)) == 0)
        `DC_STATIC_ASSERT(a_random_ways_at_most_256, WAYS <= 256)

        // Only the low WAY_WIDTH bits are used.
        /* verilator lint_off UNUSEDSIGNAL */
        wire [7:0]           q;
        /* verilator lint_on UNUSEDSIGNAL */
        wire [WAYS-1:0]      invalid;
        wire [WAY_WIDTH-1:0] highest;       // highest invalid way
        wire                 any_invalid;

        Lfsr #(.WIDTH(8)) u_lfsr(.clk, .rst_n, .q);

        Inv #(WAYS) u_inv_valid(.in(valid), .out(invalid));
        PriorityEncoder #(.SIZE(WAY_WIDTH)) u_priority_encoder(
            .in(invalid), .out(highest), .valid(any_invalid));
        Mux2 #(WAY_WIDTH) u_mux2_way(.in0(q[WAY_WIDTH-1:0]), .in1(highest), .sel(any_invalid),
                                     .out(victim_way));
    end

endmodule

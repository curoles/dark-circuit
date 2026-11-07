/* Set-associative read-write cache (a data cache), write-through, made of blocks and gates.
 *
 * Same ports, parameters and behavior as the behave version (see there; the protocol, the
 * write policy, uncached requests and READ_ONLY are CacheControl's). Per way the struct
 * CacheValidRam, CacheTagRam and CacheDataRam, a CmpEq of the tag and And3 for its hit. Then:
 *   hit      = OrReduce(hits)                hit_way = PriorityEncoder(hits), hits one-hot
 *   hit_line = per bit OrReduce over the ways of (line AND hit of the way)
 *   fill_way = DffEn (miss_taken) of CacheReplacement's victim_way
 *   touch    = load_hit OR store_write OR refill    touch_way = Mux2(hit_way, fill_way, refill)
 * and per way w:
 *   valid and tag RAM write: refill AND fill_way == w (a Decoder of fill_way)
 *   data RAM write: that OR (store_write AND hits[w]), of CacheControl's ram_wr_line
 *   line[w]  = Mux2(ram_line[w], fwd_line, fwd AND fwd_hits[w]), where fwd_hits is a DffEn
 *              (store_write) of hits: the way of the store, one-hot
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "dark_circuit_assert.svh"

module SetAssocCache import CachePkg::*, AtomicPkg::*; #(
    parameter  ADDR_WIDTH  = 32,            // byte address
    parameter  SETS_WIDTH  = 6,             // 1 << SETS_WIDTH sets
    parameter  SETS_OFFSET = 2,             // 1 << SETS_OFFSET bytes in a line (2: one word)
    parameter  WAYS        = 4,             // lines in a set, at least 2
    parameter  REPLACEMENT = REPL_LRU,      // CachePkg: REPL_LRU, REPL_RANDOM
    parameter  READ_ONLY   = 0,             // 1: loads only, no store logic
    localparam DATA_WIDTH  = 8 << SETS_OFFSET,
    localparam STRB_WIDTH  = 1 << SETS_OFFSET,  // a strobe per byte of the line
    localparam TAG_WIDTH   = ADDR_WIDTH - SETS_WIDTH - SETS_OFFSET,
    localparam WAY_WIDTH   = $clog2(WAYS)
)(
    input  wire                  clk,
    input  wire                  rst_n,         // synchronous reset, active low
    input  wire                  invalidate,    // all lines invalid

    // CPU side: requests (a channel), answers to loads
    input  wire                  req_valid,
    output wire                  req_ready,     // uncached: follows mem_req_ready, no flop
    input  wire                  req_uncached_dbg_bypass,   // debug/test mode: straight to
                                                            // memory, no lookup
    input  wire [2:0]            req_size,      // 1 << req_size bytes (AXI AxSIZE): bypass,
                                                // no cache
    input  wire                  req_nocache,   // the address may not be cached (a
                                                // device's): looked up, never filled
    // The offset in the line is not used: the cache works on whole lines. The fields of a
    // store are not used when READ_ONLY=1.
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire                  req_we,        // 1: store, 0: load
    input  wire [ADDR_WIDTH-1:0] req_addr,
    input  wire [DATA_WIDTH-1:0] req_wdata,     // store: the line with its new bytes
    input  wire [STRB_WIDTH-1:0] req_wstrb,     // store: the bytes to write
    input  atop_t                req_atop,      // ATOP_NONE, or an atomic operation (a load)
    /* verilator lint_on UNUSEDSIGNAL */
    output wire                  rsp_valid,     // rsp_data is the line a load asked for
    output wire [DATA_WIDTH-1:0] rsp_data,

    // Memory side: requests (a channel), answers to reads
    output wire                  mem_req_valid,
    input  wire                  mem_req_ready,
    output wire                  mem_req_we,
    output wire [ADDR_WIDTH-1:0] mem_req_addr,  // the line's (offset 0), or an uncached request's
    output wire [2:0]            mem_req_size,  // 1 << mem_req_size bytes: the line, or uncached
    output wire [DATA_WIDTH-1:0] mem_req_wdata, // write: the line
    output wire [STRB_WIDTH-1:0] mem_req_wstrb, // write: the bytes to write
    output atop_t                mem_req_atop,  // an atomic's operation, else ATOP_NONE
    input  wire                  mem_rsp_valid,
    input  wire [DATA_WIDTH-1:0] mem_rsp_data
);
    localparam LINE_WIDTH = ADDR_WIDTH - SETS_OFFSET;   // address bits above the offset
    localparam WAYS_POW2  = 1 << WAY_WIDTH;             // ways rounded up to a power of 2

    wire                  ram_rd;       // the RAMs read: a request taken, or a replay
    wire                  replay;       // the lookup reads its RAMs again (CacheControl)
    wire [SETS_WIDTH-1:0] rd_set;       // the set read: the request's, the lookup's on a replay
    wire                  look;         // a request taken before is looked up now (or held)
    wire [LINE_WIDTH-1:0] look_line;    // its address without the offset in the line
    wire [WAYS-1:0]       valid;        // of the ways of the set of look_line
    wire [WAYS-1:0]       hits;         // one-hot: the way that hits, 0 on a miss
    wire                  hit;
    // Bits no way reaches when WAYS is not a power of 2; valid of the encoder (hit says it).
    /* verilator lint_off UNUSEDSIGNAL */
    wire [WAYS_POW2-1:0]  fill_wr;      // one-hot: the way refill writes
    wire                  hit_way_valid;
    /* verilator lint_on UNUSEDSIGNAL */
    wire [WAYS_POW2-1:0]  hits_pow2;    // hits, padded with 0 for PriorityEncoder
    wire [WAY_WIDTH-1:0]  hit_way;
    wire [WAYS-1:0][DATA_WIDTH-1:0] ram_line;       // line of each way as its RAM read it
    wire [WAYS-1:0][DATA_WIDTH-1:0] line;           // line of each way now: forwarded or RAM
    wire [WAYS-1:0][DATA_WIDTH-1:0] line_masked;    // line of each way if it hits, else 0
    wire [DATA_WIDTH-1:0] hit_line;     // the line of the way that hits
    wire                  load_hit;
    wire                  store_write;  // a store that hits is taken by memory: write merged
    wire                  refill;       // the line from memory comes: write it
    wire                  drop;         // an atomic's line hits: clear its valid bit
    wire                  miss_taken;   // memory takes the read of a load miss
    wire                  same_set;     // the request is of the lookup's set
    wire [DATA_WIDTH-1:0] ram_wr_line;  // what a data RAM write writes: the fill or merged
    // The hit line with the store's bytes: only forwarding reads it (none when READ_ONLY).
    /* verilator lint_off UNUSEDSIGNAL */
    wire [DATA_WIDTH-1:0] merged;
    /* verilator lint_on UNUSEDSIGNAL */
    wire [WAY_WIDTH-1:0]  victim_way;   // CacheReplacement's way for a load miss found now
    wire [WAY_WIDTH-1:0]  fill_way;     // the way the line of the served miss goes into
    wire                  touch;
    wire [WAY_WIDTH-1:0]  touch_way;

    CacheControl #(.ADDR_WIDTH(ADDR_WIDTH), .SETS_OFFSET(SETS_OFFSET), .READ_ONLY(READ_ONLY))
        u_control(
            .clk, .rst_n,
            .req_valid, .req_ready, .req_uncached_dbg_bypass,
            .req_we, .req_addr, .req_wdata, .req_wstrb,
            .req_size, .req_nocache, .req_atop, .rsp_valid, .rsp_data,
            .mem_req_valid, .mem_req_ready, .mem_req_we, .mem_req_addr, .mem_req_wdata,
            .mem_req_wstrb, .mem_req_size, .mem_req_atop, .mem_rsp_valid, .mem_rsp_data,
            .ram_rd, .look, .look_line, .load_hit, .store_write, .refill, .miss_taken,
            .replay, .ram_wr_line, .merged, .drop, .hit, .hit_line, .fill_conflict(same_set));

    // The RAMs read the request's set, or the lookup's on a replay (CacheControl).
    Mux2 #(SETS_WIDTH) u_mux2_rd_set(.in0(req_addr[SETS_OFFSET +: SETS_WIDTH]),
                                     .in1(look_line[SETS_WIDTH-1:0]), .sel(replay), .out(rd_set));

    Decoder #(.SIZE(WAY_WIDTH)) u_decoder_fill(.in(fill_way), .en(refill), .out(fill_wr));

    for (genvar w = 0; w < WAYS; w++) begin: g_way
        wire [TAG_WIDTH-1:0]  tag;
        wire                  tag_eq;
        wire                  store_wr;     // a store's merged line writes this way
        wire                  data_wr;
        wire                  drop_wr;      // an atomic's drop clears this way's bit
        wire                  valid_wr;     // ... or the refill sets it

        And2 #(1) u_and2_drop_wr (.in1(drop), .in2(hits[w]), .out(drop_wr));
        Or2  #(1) u_or2_valid_wr (.in1(fill_wr[w]), .in2(drop_wr), .out(valid_wr));
        CacheValidRam #(.SETS_WIDTH(SETS_WIDTH)) u_cache_valid_ram(
            .clk, .rst_n, .invalidate,
            .rd_en(ram_rd), .rd_set(rd_set), .valid(valid[w]),
            .wr_en(valid_wr), .wr_set(look_line[SETS_WIDTH-1:0]), .wr_val(refill));

        CacheTagRam #(.SETS_WIDTH(SETS_WIDTH), .TAG_WIDTH(TAG_WIDTH)) u_cache_tag_ram(
            .clk,
            .rd_en(ram_rd), .rd_set(rd_set), .tag,
            .wr_en(fill_wr[w]), .wr_set(look_line[SETS_WIDTH-1:0]),
            .wr_tag(look_line[LINE_WIDTH-1:SETS_WIDTH]));

        And2 #(1) u_and2_store_wr(.in1(store_write), .in2(hits[w]), .out(store_wr));
        Or2  #(1) u_or2_data_wr  (.in1(fill_wr[w]), .in2(store_wr), .out(data_wr));
        CacheDataRam #(.SETS_WIDTH(SETS_WIDTH), .SETS_OFFSET(SETS_OFFSET)) u_cache_data_ram(
            .clk,
            .rd_en(ram_rd), .rd_set(rd_set), .data(ram_line[w]),
            .wr_en(data_wr), .wr_set(look_line[SETS_WIDTH-1:0]), .wr_data(ram_wr_line));

        CmpEq #(TAG_WIDTH) u_cmp_eq(.in1(tag), .in2(look_line[LINE_WIDTH-1:SETS_WIDTH]),
                                    .eq(tag_eq));
        And3  #(1) u_and3_hit(.in1(look), .in2(valid[w]), .in3(tag_eq), .out(hits[w]));
        And2  #(DATA_WIDTH) u_and2_line(.in1(line[w]), .in2({DATA_WIDTH{hits[w]}}),
                                        .out(line_masked[w]));
    end

    // A line is filled only on a miss, so a tag is in at most one way of a set.
    `DC_ASSERT(a_hits_onehot0, $onehot0(hits))

    OrReduce #(WAYS) u_or_reduce_hit(.in(hits), .out(hit));

    // hits is one-hot: its highest bit is its only one.
    assign hits_pow2 = WAYS_POW2'(hits);
    PriorityEncoder #(.SIZE(WAY_WIDTH)) u_priority_encoder_hit(
        .in(hits_pow2), .out(hit_way), .valid(hit_way_valid));

    // The line of the way that hits: the other ways are 0, so an OR per bit.
    for (genvar b = 0; b < DATA_WIDTH; b++) begin: g_bit
        wire [WAYS-1:0] ways_bit;

        for (genvar w = 0; w < WAYS; w++) begin: g_way_bit
            assign ways_bit[w] = line_masked[w][b];
        end
        OrReduce #(WAYS) u_or_reduce_line(.in(ways_bit), .out(hit_line[b]));
    end

    // The request is of the lookup's set: CacheControl's fill_conflict (taken in the refill
    // clock, its lookup is replayed), and forwarding.
    CmpEq #(SETS_WIDTH) u_cmp_eq_set(.in1(look_line[SETS_WIDTH-1:0]),
                                     .in2(req_addr[SETS_OFFSET +: SETS_WIDTH]), .eq(same_set));

    // Forwarding needs stores; a read-only cache has none of it.
    if (READ_ONLY) begin: g_read_only
        assign line = ram_line;
    end else begin: g_store
        wire                  fwd_new;      // the request taken at a store's write, same set
        wire                  fwd;          // a RAM line is older than a store's write
        wire [WAYS-1:0]       fwd_hits;     // one-hot: the way of that store
        wire [DATA_WIDTH-1:0] fwd_line;

        // Forwarding (see the behave version): decided at the edge of a read; the line and
        // the way of the store kept at its write.
        And2  #(1) u_and2_fwd (.in1(store_write), .in2(same_set), .out(fwd_new));
        DffSyncRstEn #(.WIDTH(1)) u_dff_sync_rst_en_fwd(.clk, .rst_n, .en(ram_rd), .in(fwd_new),
                                                        .out(fwd));
        DffEn #(WAYS) u_dff_en_fwd_hits(.clk, .en(store_write), .in(hits), .out(fwd_hits));
        DffEn #(DATA_WIDTH) u_dff_en_fwd_line(.clk, .en(store_write), .in(merged), .out(fwd_line));

        for (genvar w = 0; w < WAYS; w++) begin: g_line
            wire fwd_way;      // fwd_line is of this way

            And2 #(1)          u_and2_fwd_way(.in1(fwd), .in2(fwd_hits[w]), .out(fwd_way));
            Mux2 #(DATA_WIDTH) u_mux2_line   (.in0(ram_line[w]), .in1(fwd_line), .sel(fwd_way),
                                              .out(line[w]));
        end
    end

    // The replacement state is read with the request; a load hit touches its way in the
    // lookup, a store hit when memory takes it, a fill fill_way when the line comes.
    // @kb: rtl/lib/block/cache/set_assoc_cache/design
    Or3  #(1)         u_or3_touch     (.in1(load_hit), .in2(store_write), .in3(refill),
                                       .out(touch));
    Mux2 #(WAY_WIDTH) u_mux2_touch_way(.in0(hit_way), .in1(fill_way), .sel(refill),
                                       .out(touch_way));
    CacheReplacement #(.WAYS(WAYS), .SETS_WIDTH(SETS_WIDTH), .POLICY(REPLACEMENT))
        u_cache_replacement(
            .clk, .rst_n,
            .rd_en(ram_rd), .rd_set(rd_set),
            .touch, .touch_way, .valid, .victim_way);

    // The victim is taken when memory takes the read of the load miss: the random way changes
    // every clock, also while the miss is held.
    DffEn #(WAY_WIDTH) u_dff_en_fill(.clk, .en(miss_taken), .in(victim_way), .out(fill_way));

endmodule

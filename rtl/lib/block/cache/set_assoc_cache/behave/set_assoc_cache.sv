/* Set-associative read-write cache (a data cache), write-through, behavioral.
 *
 * Same ports and protocol as DirectCache. The protocol, the write policy (write-through, no
 * write-allocate), uncached requests and READ_ONLY are CacheControl's (see there): it takes
 * the requests, asks memory and answers; this module has the ways, finds the hit and keeps the
 * replacement state.
 * Each set has WAYS lines: per way a CacheValidRam, CacheTagRam and CacheDataRam, read with
 * the request; the lookup compares the tags of every way. A load miss replaces the way
 * CacheReplacement picks in the clock memory takes the read (REPLACEMENT, CachePkg:
 * REPL_LRU, REPL_RANDOM; invalid ways first). A load hit, a store hit (when memory takes it)
 * and a fill touch their way.
 * Forwarding: a store that hits writes its way at the rising edge where the next request may
 * read the set; when that request is of the same set, the RAM of that way reads the old
 * line, so the merged line is used for that way. invalidate=1 makes every line invalid;
 * allowed while no load miss is served. Reset makes every line invalid.
 * READ_ONLY=1 makes an instruction cache (SetAssocCacheRdOnly): forwarding is left out too.
 *
 *   CPU side <---> +--------------+ <---> memory side
 *                  | CacheControl |
 *                  +--------------+
 *        ram_rd, look, look_line |  ^ hit, hit_line
 *        store_write, refill,    v  |
 *        ram_wr_line, merged  +------------------------------------------+
 *                             | WAYS ways: CacheValidRam, CacheTagRam,   |
 *                             | CacheDataRam at the set; hits,           |
 *                             | forwarding, CacheReplacement, fill way   |
 *                             +------------------------------------------+
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
    logic                  ram_rd;      // the RAMs read: a request taken, or a replay
    logic                  replay;      // the lookup reads its RAMs again (CacheControl)
    logic [SETS_WIDTH-1:0] rd_set;      // the set read: the request's, the lookup's on a replay
    logic                  look;        // a request taken before is looked up now (or held)
    logic [ADDR_WIDTH-1:SETS_OFFSET] look_line;  // its address without the offset in the line
    logic [WAYS-1:0]       valid;       // of the ways of the set of look_line
    logic [WAYS-1:0][TAG_WIDTH-1:0]  tag;
    logic [WAYS-1:0][DATA_WIDTH-1:0] ram_line;  // line of each way as its RAM read it
    logic [WAYS-1:0][DATA_WIDTH-1:0] line;      // line of each way now: forwarded or ram_line
    logic [WAYS-1:0]       hits;        // one-hot: the way that hits, 0 on a miss
    logic                  hit;
    logic [WAY_WIDTH-1:0]  hit_way;
    logic [DATA_WIDTH-1:0] hit_line;    // the line of the way that hits
    logic                  load_hit;
    logic                  store_write; // a store that hits is taken by memory: write merged
    logic                  refill;      // the line from memory comes: write it
    logic                  drop;        // an atomic's line hits: clear its valid bit
    logic                  miss_taken;  // memory takes the read of a load miss
    logic                  fill_conflict;   // the request is at the place the refill writes
    logic [DATA_WIDTH-1:0] ram_wr_line; // what a data RAM write writes: the fill or merged
    // The hit line with the store's bytes: only forwarding reads it (none when READ_ONLY).
    /* verilator lint_off UNUSEDSIGNAL */
    logic [DATA_WIDTH-1:0] merged;
    /* verilator lint_on UNUSEDSIGNAL */
    logic [WAY_WIDTH-1:0]  victim_way;  // CacheReplacement's way for a load miss found now
    logic [WAY_WIDTH-1:0]  fill_way;    // the way the line of the served miss goes into

    CacheControl #(.ADDR_WIDTH(ADDR_WIDTH), .SETS_OFFSET(SETS_OFFSET), .READ_ONLY(READ_ONLY))
        u_control(
            .clk, .rst_n,
            .req_valid, .req_ready, .req_uncached_dbg_bypass,
            .req_we, .req_addr, .req_wdata, .req_wstrb,
            .req_size, .req_nocache, .req_atop, .rsp_valid, .rsp_data,
            .mem_req_valid, .mem_req_ready, .mem_req_we, .mem_req_addr, .mem_req_wdata,
            .mem_req_wstrb, .mem_req_size, .mem_req_atop, .mem_rsp_valid, .mem_rsp_data,
            .ram_rd, .look, .look_line, .load_hit, .store_write, .refill, .miss_taken,
            .replay, .ram_wr_line, .merged, .drop, .hit, .hit_line, .fill_conflict);

    // The RAMs read the request's set, or the lookup's on a replay (CacheControl).
    assign rd_set = replay ? look_line[SETS_OFFSET +: SETS_WIDTH]
                           : req_addr[SETS_OFFSET +: SETS_WIDTH];

    // The RAMs of every way read the set of the request; their answers come with look and
    // hold while a lookup is held (no request is taken). A refill writes valid, tag and data
    // of fill_way; a store that hits writes the data of hit_way.
    for (genvar w = 0; w < WAYS; w++) begin: g_way
        logic fill_wr;     // the refill writes this way
        logic data_wr;     // the refill or a store's merged line writes this way's data

        assign fill_wr = refill && fill_way == WAY_WIDTH'(w);
        assign data_wr = fill_wr || (store_write && hit_way == WAY_WIDTH'(w));

        CacheValidRam #(.SETS_WIDTH(SETS_WIDTH)) u_cache_valid_ram(
            .clk, .rst_n, .invalidate,
            .rd_en(ram_rd), .rd_set(rd_set), .valid(valid[w]),
            .wr_en(fill_wr || (drop && hits[w])),   // an atomic's drop clears it
            .wr_set(look_line[SETS_OFFSET +: SETS_WIDTH]), .wr_val(refill));

        CacheTagRam #(.SETS_WIDTH(SETS_WIDTH), .TAG_WIDTH(TAG_WIDTH)) u_cache_tag_ram(
            .clk,
            .rd_en(ram_rd), .rd_set(rd_set), .tag(tag[w]),
            .wr_en(fill_wr), .wr_set(look_line[SETS_OFFSET +: SETS_WIDTH]),
            .wr_tag(look_line[ADDR_WIDTH-1 -: TAG_WIDTH]));

        CacheDataRam #(.SETS_WIDTH(SETS_WIDTH), .SETS_OFFSET(SETS_OFFSET)) u_cache_data_ram(
            .clk,
            .rd_en(ram_rd), .rd_set(rd_set), .data(ram_line[w]),
            .wr_en(data_wr), .wr_set(look_line[SETS_OFFSET +: SETS_WIDTH]),
            .wr_data(ram_wr_line));

        assign hits[w] = look && valid[w] && tag[w] == look_line[ADDR_WIDTH-1 -: TAG_WIDTH];
    end

    // A line is filled only on a miss, so a tag is in at most one way of a set.
    `DC_ASSERT(a_hits_onehot0, $onehot0(hits))

    // Index and line of the way that hits: OR of the ways selected by the one-hot hits.
    function automatic [WAY_WIDTH-1:0] index_of(input [WAYS-1:0] one_hot);
        index_of = '0;
        for (int w = 0; w < WAYS; w++)
            if (one_hot[w])
                index_of = index_of | WAY_WIDTH'(w);
    endfunction

    function automatic [DATA_WIDTH-1:0] line_of(input [WAYS-1:0]                  one_hot,
                                                input [WAYS-1:0][DATA_WIDTH-1:0] d);
        line_of = '0;
        for (int w = 0; w < WAYS; w++)
            if (one_hot[w])
                line_of = line_of | d[w];
    endfunction

    assign hit      = |hits;
    assign hit_way  = index_of(hits);
    assign hit_line = line_of(hits, line);

    // The request is at the place the refill writes (taken in the refill clock, CacheControl
    // replays its lookup): the same set.
    assign fill_conflict =
        req_addr[SETS_OFFSET +: SETS_WIDTH] == look_line[SETS_OFFSET +: SETS_WIDTH];

    // Forwarding needs stores; a read-only cache has none of it.
    if (READ_ONLY) begin: g_read_only
        assign line = ram_line;
    end else begin: g_store
        logic                  fwd;         // the RAM of fwd_way read a line older than a store
        logic [WAY_WIDTH-1:0]  fwd_way;
        logic [DATA_WIDTH-1:0] fwd_line;

        // Forwarding: the request taken at the edge of a store's write read the old line of
        // its way when it is of the same set.
        always_ff @(posedge clk)
            if (!rst_n)
                fwd <= 1'b0;
            else if (ram_rd)
                fwd <= store_write &&
                       look_line[SETS_OFFSET +: SETS_WIDTH] == req_addr[SETS_OFFSET +: SETS_WIDTH];

        always_ff @(posedge clk)
            if (store_write) begin
                fwd_way  <= hit_way;
                fwd_line <= merged;
            end

        for (genvar w = 0; w < WAYS; w++) begin: g_line
            assign line[w] = (fwd && fwd_way == WAY_WIDTH'(w)) ? fwd_line : ram_line[w];
        end
    end

    // The replacement state of the set is read with the request. A load hit touches its way
    // in the lookup, a store hit when memory takes it, a fill fill_way when the line comes.
    // @kb: rtl/lib/block/cache/set_assoc_cache/design
    CacheReplacement #(.WAYS(WAYS), .SETS_WIDTH(SETS_WIDTH), .POLICY(REPLACEMENT))
        u_cache_replacement(
            .clk, .rst_n,
            .rd_en(ram_rd), .rd_set(rd_set),
            .touch(load_hit || store_write || refill),
            .touch_way(refill ? fill_way : hit_way),
            .valid, .victim_way);

    // The victim is taken when memory takes the read: the random way changes every clock,
    // also while the miss is held.
    always_ff @(posedge clk)
        if (miss_taken)
            fill_way <= victim_way;

endmodule

/* Set-associative read-write cache (a data cache), write-through, behavioral.
 *
 * Same ports and protocol as DirectCache (see there): a load or a store is taken at a rising
 * edge with req_valid=1 and req_ready=1 and looked up in the clock after; a load that hits
 * answers then; a load that misses reads its line from memory, answers with it and writes
 * it; a store is done when it is taken and gets no answer. Write-through, no write-allocate:
 * every store goes to memory from its lookup; a store that hits also merges its bytes into
 * the line of its way, written when memory takes the store; a store that misses leaves the
 * cache as it is. Memory side: one valid/ready channel in program order, a read answered by
 * mem_rsp_valid one or more clocks after memory took it.
 * Each set has WAYS lines: per way a CacheValidRam, CacheTagRam and CacheDataRam, read with
 * the request; the lookup compares the tags of every way. A load miss replaces the way
 * CacheReplacement picks in the clock memory takes the read (REPLACEMENT, CachePkg:
 * REPL_LRU, REPL_RANDOM; invalid ways first). A load hit, a store hit (when memory takes it)
 * and a fill touch their way.
 * Forwarding: a store that hits writes its way at the rising edge where the next request may
 * read the set; when that request is of the same set, the RAM of that way reads the old
 * line, so the merged line is used for that way. invalidate=1 makes every line invalid;
 * allowed while no load miss is served. Reset makes every line invalid.
 * Uncached: a request with req_uncached=1 does not use the lines (no lookup, fill or
 * update) and passes straight to the memory side: it is taken when nothing is looked up or
 * served, in the clock memory takes it, so req_ready then follows mem_req_ready without a
 * flop; a load is answered in the clock memory answers, with memory's line. An address is
 * used either cached or uncached, never both: the cache does not check.
 * READ_ONLY=1 makes an instruction cache (SetAssocCacheRdOnly): no stores (req_we, req_wdata
 * and req_wstrb are not used; mem_req_we, mem_req_wdata and mem_req_wstrb are 0), so the
 * logic only stores need (their fields of the request, the merge, forwarding) is left out.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "dark_circuit_assert.svh"

module SetAssocCache import CachePkg::*; #(
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
    input  wire                  req_uncached,  // the request bypasses the lines
    // The offset in the line is not used: the cache works on whole lines. The fields of a
    // store are not used when READ_ONLY=1.
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire                  req_we,        // 1: store, 0: load
    input  wire [ADDR_WIDTH-1:0] req_addr,
    input  wire [DATA_WIDTH-1:0] req_wdata,     // store: the line with its new bytes
    input  wire [STRB_WIDTH-1:0] req_wstrb,     // store: the bytes to write
    /* verilator lint_on UNUSEDSIGNAL */
    output wire                  rsp_valid,     // rsp_data is the line a load asked for
    output wire [DATA_WIDTH-1:0] rsp_data,

    // Memory side: requests (a channel), answers to reads
    output wire                  mem_req_valid,
    input  wire                  mem_req_ready,
    output wire                  mem_req_we,
    output wire [ADDR_WIDTH-1:0] mem_req_addr,  // address of the line (offset 0)
    output wire [DATA_WIDTH-1:0] mem_req_wdata, // write: the line
    output wire [STRB_WIDTH-1:0] mem_req_wstrb, // write: the bytes to write
    input  wire                  mem_rsp_valid,
    input  wire [DATA_WIDTH-1:0] mem_rsp_data
);
    logic                  accept;      // a request is taken in this clock
    logic                  look;        // a request taken before is looked up now (or held)
    logic [ADDR_WIDTH-1:SETS_OFFSET] look_line;  // its address without the offset in the line
    logic                  look_we;
    logic [WAYS-1:0]       valid;       // of the ways of the set of look_line
    logic [WAYS-1:0][TAG_WIDTH-1:0]  tag;
    logic [WAYS-1:0][DATA_WIDTH-1:0] ram_line;  // line of each way as its RAM read it
    logic [WAYS-1:0][DATA_WIDTH-1:0] line;      // line of each way now: forwarded or ram_line
    logic [WAYS-1:0]       hits;        // one-hot: the way that hits, 0 on a miss
    logic                  hit;
    logic [WAY_WIDTH-1:0]  hit_way;
    logic [DATA_WIDTH-1:0] hit_line;    // the line of the way that hits
    logic                  store;       // a store is looked up
    logic                  load_hit;
    logic                  load_miss;
    logic                  look_req;    // the lookup asks memory: a store or a load miss
    logic                  held;        // its memory request is not taken: the lookup stays
    logic                  store_write; // a store that hits is taken by memory: write merged
    logic                  waiting;     // a load miss is served: memory has not answered yet
    logic                  refill;      // the line from memory comes: write it
    logic [DATA_WIDTH-1:0] ram_wr_line; // what a data RAM write writes: the fill or merged
    logic [WAY_WIDTH-1:0]  victim_way;  // CacheReplacement's way for a load miss found now
    logic [WAY_WIDTH-1:0]  fill_way;    // the way the line of the served miss goes into
    logic                  unc_waiting; // memory took an uncached read, has not answered yet
    logic                  unc_busy;    // ... and does not answer now
    logic                  idle;        // nothing looked up or served: uncached may pass
    logic                  unc_pass;    // an uncached request goes to memory now

    // A cached request is taken only when the lookup is done: no load miss found or served,
    // memory took the lookup's own request, no uncached read waits. An uncached one passes to
    // memory when the cache is idle and is taken when memory takes it.
    // @kb: rtl/lib/block/cache/uncached
    assign unc_busy  = unc_waiting && !mem_rsp_valid;
    assign idle      = !look && !waiting && !unc_busy;
    assign unc_pass  = req_valid && req_uncached && idle;
    assign req_ready = req_uncached ? idle && mem_req_ready
                                    : !waiting && !load_miss && !held && !unc_busy;
    assign accept    = req_valid && !req_uncached && req_ready;

    always_ff @(posedge clk)
        if (!rst_n) look <= 1'b0;
        else        look <= accept || held;

    always_ff @(posedge clk)
        if (accept)
            look_line <= req_addr[ADDR_WIDTH-1:SETS_OFFSET];

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
            .rd_en(accept), .rd_set(req_addr[SETS_OFFSET +: SETS_WIDTH]), .valid(valid[w]),
            .wr_en(fill_wr), .wr_set(look_line[SETS_OFFSET +: SETS_WIDTH]), .wr_val(1'b1));

        CacheTagRam #(.SETS_WIDTH(SETS_WIDTH), .TAG_WIDTH(TAG_WIDTH)) u_cache_tag_ram(
            .clk,
            .rd_en(accept), .rd_set(req_addr[SETS_OFFSET +: SETS_WIDTH]), .tag(tag[w]),
            .wr_en(fill_wr), .wr_set(look_line[SETS_OFFSET +: SETS_WIDTH]),
            .wr_tag(look_line[ADDR_WIDTH-1 -: TAG_WIDTH]));

        CacheDataRam #(.SETS_WIDTH(SETS_WIDTH), .SETS_OFFSET(SETS_OFFSET)) u_cache_data_ram(
            .clk,
            .rd_en(accept), .rd_set(req_addr[SETS_OFFSET +: SETS_WIDTH]), .data(ram_line[w]),
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

    assign hit       = |hits;
    assign hit_way   = index_of(hits);
    assign hit_line  = line_of(hits, line);
    assign store     = look && look_we;
    assign load_hit  = look && !look_we && hit;
    assign load_miss = look && !look_we && !hit;

    // Write-through: a store always goes to memory; a load only when it misses. A cached
    // request comes from the lookup's registers; an uncached one straight from the CPU side
    // (only while idle: never both); valid does not depend on mem_req_ready (rule 3). The
    // fields of a write are set in the branches below.
    assign look_req      = store || load_miss;
    assign mem_req_valid = unc_pass || look_req;
    assign held          = look_req && !mem_req_ready;
    assign mem_req_addr  = unc_pass ? {req_addr[ADDR_WIDTH-1:SETS_OFFSET], {SETS_OFFSET{1'b0}}}
                                    : {look_line, {SETS_OFFSET{1'b0}}};

    // The merged line goes into the cache once: in the clock memory takes the store.
    function automatic [DATA_WIDTH-1:0] merge(input [DATA_WIDTH-1:0] old,
                                              input [DATA_WIDTH-1:0] new_bytes,
                                              input [STRB_WIDTH-1:0] strb);
        merge = old;
        for (int b = 0; b < STRB_WIDTH; b++)
            if (strb[b])
                merge[8*b +: 8] = new_bytes[8*b +: 8];
    endfunction

    // The logic only stores need; a read-only cache has none of it. Both branches drive
    // look_we, store_write, ram_wr_line, line and the fields of a memory write (mem_req_we,
    // mem_req_wdata, mem_req_wstrb).
    // @kb: rtl/lib/block/cache/read_only
    if (READ_ONLY) begin: g_read_only
        assign look_we     = 1'b0;
        assign store_write = 1'b0;
        assign ram_wr_line = mem_rsp_data;
        assign line        = ram_line;

        assign mem_req_we    = 1'b0;
        assign mem_req_wdata = '0;
        assign mem_req_wstrb = '0;
    end else begin: g_store
        logic [DATA_WIDTH-1:0] look_wdata;
        logic [STRB_WIDTH-1:0] look_wstrb;
        logic                  fwd;         // the RAM of fwd_way read a line older than a store
        logic [WAY_WIDTH-1:0]  fwd_way;
        logic [DATA_WIDTH-1:0] fwd_line;
        logic [DATA_WIDTH-1:0] merged;      // hit_line with the bytes of the store

        always_ff @(posedge clk)
            if (accept) begin
                look_we    <= req_we;
                look_wdata <= req_wdata;
                look_wstrb <= req_wstrb;
            end

        // A memory write: an uncached store as it comes, else the lookup's store.
        assign mem_req_we    = unc_pass ? req_we    : look_we;
        assign mem_req_wdata = unc_pass ? req_wdata : look_wdata;
        assign mem_req_wstrb = unc_pass ? req_wstrb : look_wstrb;

        assign merged      = merge(hit_line, look_wdata, look_wstrb);
        assign store_write = store && hit && mem_req_ready;
        assign ram_wr_line = refill ? mem_rsp_data : merged;

        // Forwarding: the request taken at the edge of a store's write read the old line of
        // its way when it is of the same set.
        always_ff @(posedge clk)
            if (!rst_n)
                fwd <= 1'b0;
            else if (accept)
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
            .rd_en(accept), .rd_set(req_addr[SETS_OFFSET +: SETS_WIDTH]),
            .touch(load_hit || store_write || refill),
            .touch_way(refill ? fill_way : hit_way),
            .valid, .victim_way);

    // The victim is taken when memory takes the read: the random way changes every clock,
    // also while the miss is held.
    always_ff @(posedge clk)
        if (load_miss && mem_req_ready)
            fill_way <= victim_way;

    // A load miss is served from the clock memory takes its read until the answer comes
    // (look_line holds: no request is taken meanwhile).
    always_ff @(posedge clk)
        if (!rst_n)                          waiting <= 1'b0;
        else if (load_miss && mem_req_ready) waiting <= 1'b1;
        else if (mem_rsp_valid)              waiting <= 1'b0;

    assign refill = waiting && mem_rsp_valid;

    // A lookup ends when memory takes its read, and no request is taken while the miss is
    // served: so a refill never meets a store's write, and the refill writes look_line's set.
    `DC_ASSERT(a_no_look_while_waiting, !(look && waiting))

    // An uncached read is served from the clock memory takes it until the answer comes; its
    // line is not written into the cache.
    always_ff @(posedge clk)
        if (!rst_n)                                        unc_waiting <= 1'b0;
        else if (unc_pass && mem_req_ready && !mem_req_we) unc_waiting <= 1'b1;
        else if (mem_rsp_valid)                            unc_waiting <= 1'b0;

    // It passed while idle, and nothing is taken while it waits: alone with memory.
    `DC_ASSERT(a_unc_alone, !(unc_waiting && (look || waiting)))

    assign rsp_valid = load_hit || refill || (unc_waiting && mem_rsp_valid);
    assign rsp_data  = (waiting || unc_waiting) ? mem_rsp_data : hit_line;

endmodule

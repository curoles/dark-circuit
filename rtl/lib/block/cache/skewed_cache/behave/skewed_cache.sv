/* Two-way skewed-associative read-write cache (a data cache), write-through, behavioral.
 *
 * Same ports and protocol as DirectCache and SetAssocCache (see DirectCache): a load or a
 * store is taken at a rising edge with req_valid=1 and req_ready=1 and looked up in the clock
 * after; a load that hits answers then; a load that misses reads its line from memory,
 * answers with it and writes it; a store is done when it is taken and gets no answer.
 * Write-through, no write-allocate: every store goes to memory from its lookup; a store that
 * hits also merges its bytes into its line, written when memory takes the store; a store
 * that misses leaves the cache as it is. Memory side: one valid/ready channel in program
 * order, a read answered by mem_rsp_valid one or more clocks after memory took it.
 * Skewed (A. Seznec, A case for two-way skewed-associative caches, ISCA 1993): each way has
 * a line index of its own, f0 = set and f1 = set ^ the low SETS_WIDTH bits of the tag, so
 * lines that conflict in one way usually do not in the other. Per way a CacheValidRam,
 * CacheTagRam and CacheDataRam, read with the request at the way's index; the lookup
 * compares the tags of both ways (a line is in at most one: it is filled only on a miss).
 * Replacement: the two candidates of an address are in different "sets", so the state is per
 * line: a recent bit. A load hit, a store hit (when memory takes it) and a fill set their
 * line's bit and clear the other candidate's; a load miss replaces an invalid candidate (way
 * 1 first), else the one whose bit is clear, else (both alike: the bits are shared by other
 * pairs) way 0, taken when memory takes the read. The bits are flops without reset (a fill
 * writes the bit of the line it makes valid; the bits are compared only when both candidates
 * are valid), read in the lookup clock, so a lookup sees the update of the one before.
 * Forwarding: a store that hits writes its line at the rising edge where the next request may
 * read the RAMs; when that request has the store's index in the store's way, that RAM reads
 * the old line, so the merged line is used for that way. invalidate=1 makes every line
 * invalid; allowed while no load miss is served. Reset makes every line invalid.
 * READ_ONLY=1 makes an instruction cache (SkewedCacheRdOnly): no stores (req_we, req_wdata
 * and req_wstrb are not used; mem_req_we, mem_req_wdata and mem_req_wstrb are 0), so the
 * logic only stores need (their fields of the request, the merge, forwarding) is left out.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "dark_circuit_assert.svh"

module SkewedCache #(
    parameter  ADDR_WIDTH  = 32,            // byte address
    parameter  SETS_WIDTH  = 6,             // 1 << SETS_WIDTH lines in each way
    parameter  SETS_OFFSET = 2,             // 1 << SETS_OFFSET bytes in a line (2: one word)
    parameter  READ_ONLY   = 0,             // 1: loads only, no store logic
    localparam DATA_WIDTH  = 8 << SETS_OFFSET,
    localparam STRB_WIDTH  = 1 << SETS_OFFSET,  // a strobe per byte of the line
    localparam TAG_WIDTH   = ADDR_WIDTH - SETS_WIDTH - SETS_OFFSET,
    localparam SETS        = 1 << SETS_WIDTH
)(
    input  wire                  clk,
    input  wire                  rst_n,         // synchronous reset, active low
    input  wire                  invalidate,    // all lines invalid

    // CPU side: requests (a channel), answers to loads
    input  wire                  req_valid,
    output wire                  req_ready,
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
    `DC_STATIC_ASSERT(a_tag_covers_index, TAG_WIDTH >= SETS_WIDTH)

    typedef logic [ADDR_WIDTH-1:SETS_OFFSET] line_t;    // an address without the offset

    logic                  accept;      // a request is taken in this clock
    logic                  look;        // a request taken before is looked up now (or held)
    line_t                 look_line;   // its line
    logic                  look_we;
    logic [DATA_WIDTH-1:0] look_wdata;
    logic [STRB_WIDTH-1:0] look_wstrb;
    logic [1:0][SETS_WIDTH-1:0] look_index;  // its index in each way
    logic [1:0][SETS_WIDTH-1:0] req_index;   // the index of the request in each way
    logic [1:0]            valid;       // of the candidates of look_line
    logic [1:0][TAG_WIDTH-1:0]  tag;
    logic [1:0][DATA_WIDTH-1:0] ram_line;    // line of each candidate as its RAM read it
    logic [1:0][DATA_WIDTH-1:0] line;        // line of each candidate now: forwarded or RAM
    logic [1:0]            hits;        // one-hot: the way that hits, 0 on a miss
    logic                  hit;
    logic                  hit_way;
    logic [DATA_WIDTH-1:0] hit_line;    // the line of the way that hits
    logic                  store;       // a store is looked up
    logic                  load_hit;
    logic                  load_miss;
    logic                  held;        // its memory request is not taken: the lookup stays
    logic                  store_write; // a store that hits is taken by memory: write merged
    logic                  waiting;     // a load miss is served: memory has not answered yet
    logic                  refill;      // the line from memory comes: write it
    logic [DATA_WIDTH-1:0] ram_wr_line; // what a data RAM write writes: the fill or merged
    logic                  victim_way;  // the way a load miss found now replaces
    logic                  fill_way;    // the way the line of the served miss goes into
    logic                  touch;       // the recent bits change
    logic                  touch_way;
    logic                  recent [2][SETS];    // per line: used more recently than its pair
    logic [1:0]            look_recent; // the recent bits of the candidates of look_line

    // @kb: rtl/lib/block/cache/skewed_cache_rd_only/design
    // The index of line l in way w: f0 = set, f1 = set ^ the low bits of the tag (the higher
    // bits of the tag do not matter).
    /* verilator lint_off UNUSEDSIGNAL */
    function automatic [SETS_WIDTH-1:0] index_of(input int w, input line_t l);
        logic [SETS_WIDTH-1:0] set;
        logic [SETS_WIDTH-1:0] tag_low;
        set     = l[SETS_OFFSET +: SETS_WIDTH];
        tag_low = l[SETS_OFFSET + SETS_WIDTH +: SETS_WIDTH];
        return (w == 0) ? set : set ^ tag_low;
    endfunction
    /* verilator lint_on UNUSEDSIGNAL */

    // A request is taken only when the lookup is done: no load miss found or served, and
    // memory took the lookup's own request.
    assign req_ready = !waiting && !load_miss && !held;
    assign accept    = req_valid && req_ready;

    always_ff @(posedge clk)
        if (!rst_n) look <= 1'b0;
        else        look <= accept || held;

    always_ff @(posedge clk)
        if (accept)
            look_line <= req_addr[ADDR_WIDTH-1:SETS_OFFSET];

    // The RAMs of each way read the request's index in that way; their answers come with
    // look and hold while a lookup is held. A refill writes valid, tag and data of fill_way;
    // a store that hits writes the data of its way, at look_line's index there.
    for (genvar w = 0; w < 2; w++) begin: g_way
        logic fill_wr;     // the refill writes this way
        logic data_wr;     // the refill or a store's merged line writes this way's data

        assign req_index[w]  = index_of(w, req_addr[ADDR_WIDTH-1:SETS_OFFSET]);
        assign look_index[w] = index_of(w, look_line);
        assign fill_wr       = refill && fill_way == 1'(w);
        assign data_wr       = fill_wr || (store_write && hits[w]);

        CacheValidRam #(.SETS_WIDTH(SETS_WIDTH)) u_cache_valid_ram(
            .clk, .rst_n, .invalidate,
            .rd_en(accept), .rd_set(req_index[w]), .valid(valid[w]),
            .wr_en(fill_wr), .wr_set(look_index[w]), .wr_val(1'b1));

        CacheTagRam #(.SETS_WIDTH(SETS_WIDTH), .TAG_WIDTH(TAG_WIDTH)) u_cache_tag_ram(
            .clk,
            .rd_en(accept), .rd_set(req_index[w]), .tag(tag[w]),
            .wr_en(fill_wr), .wr_set(look_index[w]),
            .wr_tag(look_line[ADDR_WIDTH-1 -: TAG_WIDTH]));

        CacheDataRam #(.SETS_WIDTH(SETS_WIDTH), .SETS_OFFSET(SETS_OFFSET)) u_cache_data_ram(
            .clk,
            .rd_en(accept), .rd_set(req_index[w]), .data(ram_line[w]),
            .wr_en(data_wr), .wr_set(look_index[w]),
            .wr_data(ram_wr_line));

        assign hits[w]        = look && valid[w] && tag[w] == look_line[ADDR_WIDTH-1 -: TAG_WIDTH];
        assign look_recent[w] = recent[w][look_index[w]];
    end

    // A line is filled only on a miss, so it is in at most one way.
    `DC_ASSERT(a_hits_onehot0, $onehot0(hits))

    assign hit       = |hits;
    assign hit_way   = hits[1];
    assign hit_line  = hit_way ? line[1] : line[0];
    assign store     = look && look_we;
    assign load_hit  = look && !look_we && hit;
    assign load_miss = look && !look_we && !hit;

    // Write-through: a store always goes to memory; a load only when it misses. The request
    // comes from the lookup's registers, so valid does not depend on any input.
    assign mem_req_valid = store || load_miss;
    assign held          = mem_req_valid && !mem_req_ready;
    assign mem_req_we    = look_we;
    assign mem_req_addr  = {look_line, {SETS_OFFSET{1'b0}}};
    assign mem_req_wdata = look_wdata;
    assign mem_req_wstrb = look_wstrb;

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
    // look_we, look_wdata, look_wstrb, store_write, ram_wr_line and line.
    // @kb: rtl/lib/block/cache/read_only
    if (READ_ONLY) begin: g_read_only
        assign look_we     = 1'b0;
        assign look_wdata  = '0;
        assign look_wstrb  = '0;
        assign store_write = 1'b0;
        assign ram_wr_line = mem_rsp_data;
        assign line        = ram_line;
    end else begin: g_store
        logic [DATA_WIDTH-1:0] fwd_line;
        logic [DATA_WIDTH-1:0] merged;      // hit_line with the bytes of the store

        always_ff @(posedge clk)
            if (accept) begin
                look_we    <= req_we;
                look_wdata <= req_wdata;
                look_wstrb <= req_wstrb;
            end

        assign merged      = merge(hit_line, look_wdata, look_wstrb);
        assign store_write = store && hit && mem_req_ready;
        assign ram_wr_line = refill ? mem_rsp_data : merged;

        always_ff @(posedge clk)
            if (store_write)
                fwd_line <= merged;

        for (genvar w = 0; w < 2; w++) begin: g_line
            logic fwd;     // this way's RAM read a line older than a store

            // Forwarding: the request taken at the edge of a store's write read the old line
            // of this way when the store hit here at the request's index in this way.
            always_ff @(posedge clk)
                if (!rst_n)
                    fwd <= 1'b0;
                else if (accept)
                    fwd <= store_write && hits[w] && look_index[w] == req_index[w];

            assign line[w] = fwd ? fwd_line : ram_line[w];
        end
    end

    // The victim of a load miss: an invalid candidate (way 1 first), else the one not
    // recently used, else way 0. An assign, not always_comb (Icarus: constant selects).
    assign victim_way = !valid[1]                     ? 1'b1 :
                        !valid[0]                     ? 1'b0 :
                        look_recent[0] != look_recent[1] ? look_recent[0] :
                                                        1'b0;

    // A load hit touches its way in the lookup, a store hit when memory takes it, a fill
    // fill_way when the line comes (look_line stays: no request is taken meanwhile). The
    // touched line becomes recent, the other candidate not.
    // @kb: rtl/lib/block/cache/skewed_cache/design
    assign touch     = load_hit || store_write || refill;
    assign touch_way = refill ? fill_way : hit_way;

    always_ff @(posedge clk)
        if (touch) begin
            recent[0][look_index[0]] <= !touch_way;
            recent[1][look_index[1]] <= touch_way;
        end

    // The victim is taken when memory takes the read.
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
    // served: so a refill never meets a store's write, and the refill writes look_line's
    // indices.
    `DC_ASSERT(a_no_look_while_waiting, !(look && waiting))

    assign rsp_valid = load_hit || refill;
    assign rsp_data  = waiting ? mem_rsp_data : hit_line;

endmodule

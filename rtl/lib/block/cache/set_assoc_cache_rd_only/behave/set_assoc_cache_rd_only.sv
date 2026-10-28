/* Set-associative read-only cache (an instruction cache), behavioral.
 *
 * Same ports and protocol as DirectCacheRdOnly (see there): a byte address is tag | set |
 * offset; the CPU side takes a request on a valid/ready channel and answers a hit one clock
 * later; a miss asks memory for the line on a valid/ready channel (held until memory takes
 * it) and answers with the line; invalidate makes every line invalid (allowed while no miss
 * is served). Each set has WAYS lines: per way a CacheValidRam, CacheTagRam and
 * CacheDataRam, all read with the request; the lookup compares the tags of every way. A miss
 * replaces the way CacheReplacement picks in the clock memory takes the read (REPLACEMENT,
 * CachePkg: REPL_LRU, REPL_RANDOM; invalid ways first); a hit and a fill touch their way.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "dark_circuit_assert.svh"

module SetAssocCacheRdOnly import CachePkg::*; #(
    parameter  ADDR_WIDTH  = 32,            // byte address
    parameter  SETS_WIDTH  = 6,             // 1 << SETS_WIDTH sets
    parameter  SETS_OFFSET = 2,             // 1 << SETS_OFFSET bytes in a line (2: one word)
    parameter  WAYS        = 4,             // lines in a set, at least 2
    parameter  REPLACEMENT = REPL_LRU,      // CachePkg: REPL_LRU, REPL_RANDOM
    localparam DATA_WIDTH  = 8 << SETS_OFFSET,
    localparam TAG_WIDTH   = ADDR_WIDTH - SETS_WIDTH - SETS_OFFSET,
    localparam WAY_WIDTH   = $clog2(WAYS)
)(
    input  wire                  clk,
    input  wire                  rst_n,         // synchronous reset, active low
    input  wire                  invalidate,    // all lines invalid

    // CPU side
    input  wire                  req_valid,
    // The offset in the line is not used: the cache answers whole lines.
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire [ADDR_WIDTH-1:0] req_addr,
    /* verilator lint_on UNUSEDSIGNAL */
    output wire                  req_ready,     // 0 while a miss is served: hold the request
    output wire                  rsp_valid,     // rsp_data is the line asked for
    output wire [DATA_WIDTH-1:0] rsp_data,

    // Memory side
    output wire                  mem_req_valid,
    input  wire                  mem_req_ready,
    output wire [ADDR_WIDTH-1:0] mem_req_addr,  // address of the line (offset 0)
    input  wire                  mem_rsp_valid,
    input  wire [DATA_WIDTH-1:0] mem_rsp_data
);
    logic                  accept;      // a request is taken in this clock
    logic                  look;        // the request of the clock before is looked up now
    logic [ADDR_WIDTH-1:SETS_OFFSET] look_line;  // its address without the offset in the line
    logic [WAYS-1:0]       valid;       // of the ways of the set of look_line
    logic [WAYS-1:0][TAG_WIDTH-1:0]  tag;   // of each way
    logic [WAYS-1:0][DATA_WIDTH-1:0] data;
    logic [WAYS-1:0]       hits;        // one-hot: the way that hits, 0 on a miss
    logic                  hit;
    logic                  miss;
    logic                  held;        // memory does not take the miss's read: it stays
    logic [WAY_WIDTH-1:0]  hit_way;
    logic [WAY_WIDTH-1:0]  victim_way;  // CacheReplacement's way for a miss found now
    logic [WAY_WIDTH-1:0]  fill_way;    // the way the line of the served miss goes into
    logic                  waiting;     // a miss is served: the memory has not answered yet
    logic                  refill;      // the line from memory comes: write it
    logic [DATA_WIDTH-1:0] hit_data;

    // A request is taken only when nothing waits: neither a miss found now nor one served.
    assign req_ready = !waiting && !miss;
    assign accept    = req_valid && req_ready;

    always_ff @(posedge clk)
        if (!rst_n) look <= 1'b0;
        else        look <= accept || held;

    always_ff @(posedge clk)
        if (accept)
            look_line <= req_addr[ADDR_WIDTH-1:SETS_OFFSET];

    // The RAMs of every way read the set of the request; their answers come with look. The
    // line from memory goes into fill_way only.
    for (genvar w = 0; w < WAYS; w++) begin: g_way
        logic wr_en;

        assign wr_en = refill && fill_way == WAY_WIDTH'(w);

        CacheValidRam #(.SETS_WIDTH(SETS_WIDTH)) u_cache_valid_ram(
            .clk, .rst_n, .invalidate,
            .rd_en(accept), .rd_set(req_addr[SETS_OFFSET +: SETS_WIDTH]), .valid(valid[w]),
            .wr_en, .wr_set(look_line[SETS_OFFSET +: SETS_WIDTH]), .wr_val(1'b1));

        CacheTagRam #(.SETS_WIDTH(SETS_WIDTH), .TAG_WIDTH(TAG_WIDTH)) u_cache_tag_ram(
            .clk,
            .rd_en(accept), .rd_set(req_addr[SETS_OFFSET +: SETS_WIDTH]), .tag(tag[w]),
            .wr_en, .wr_set(look_line[SETS_OFFSET +: SETS_WIDTH]),
            .wr_tag(look_line[ADDR_WIDTH-1 -: TAG_WIDTH]));

        CacheDataRam #(.SETS_WIDTH(SETS_WIDTH), .SETS_OFFSET(SETS_OFFSET)) u_cache_data_ram(
            .clk,
            .rd_en(accept), .rd_set(req_addr[SETS_OFFSET +: SETS_WIDTH]), .data(data[w]),
            .wr_en, .wr_set(look_line[SETS_OFFSET +: SETS_WIDTH]), .wr_data(mem_rsp_data));

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
    assign miss     = look && !hit;
    assign hit_way  = index_of(hits);
    assign hit_data = line_of(hits, data);

    // The replacement state of the set is read with the request too. A hit touches its way
    // in the lookup; a fill touches fill_way when the line comes (the set stays the one read:
    // no request is taken meanwhile).
    CacheReplacement #(.WAYS(WAYS), .SETS_WIDTH(SETS_WIDTH), .POLICY(REPLACEMENT))
        u_cache_replacement(
            .clk, .rst_n,
            .rd_en(accept), .rd_set(req_addr[SETS_OFFSET +: SETS_WIDTH]),
            .touch(hit || refill), .touch_way(refill ? fill_way : hit_way),
            .valid, .victim_way);

    // A miss asks memory for its line and holds the request, with its lookup, until memory
    // takes it; then the cache waits for the answer, which it passes on and writes (look_line
    // holds: no request is taken meanwhile).
    assign held = miss && !mem_req_ready;

    // The victim is taken when memory takes the read: the random way changes every clock,
    // also while the miss is held.
    always_ff @(posedge clk)
        if (miss && mem_req_ready)
            fill_way <= victim_way;

    always_ff @(posedge clk)
        if (!rst_n)                     waiting <= 1'b0;
        else if (miss && mem_req_ready) waiting <= 1'b1;
        else if (mem_rsp_valid)         waiting <= 1'b0;

    // A lookup ends when memory takes its read, and no request is taken while the miss is
    // served: so the refill writes the set of look_line.
    `DC_ASSERT(a_no_look_while_waiting, !(look && waiting))

    assign refill        = waiting && mem_rsp_valid;
    assign mem_req_valid = miss;
    assign mem_req_addr  = {look_line, {SETS_OFFSET{1'b0}}};
    assign rsp_valid     = hit || refill;
    assign rsp_data      = waiting ? mem_rsp_data : hit_data;

endmodule

/* Two-way skewed-associative read-only cache (an instruction cache), behavioral.
 *
 * Same ports and protocol as SetAssocCacheRdOnly and DirectCacheRdOnly (see there): a byte
 * address is tag | set | offset; the CPU side takes a request on a valid/ready channel and
 * answers a hit one clock later; a miss asks memory for the line on a valid/ready channel
 * (held until memory takes it) and answers with the line; invalidate makes every line
 * invalid (allowed while no miss is served).
 *
 * Skewed (A. Seznec, A case for two-way skewed-associative caches, ISCA 1993): each way has
 * a line index of its own, f0 = set and f1 = set ^ the low SETS_WIDTH bits of the tag, so
 * lines that conflict in one way usually do not in the other. Per way a CacheValidRam,
 * CacheTagRam and CacheDataRam, read with the request at the way's index; the lookup
 * compares the tags of both ways (a line is in at most one: it is filled only on a miss).
 * Replacement: the two candidates of an address are in different "sets", so the state is per
 * line: a recent bit. A hit or a fill sets its line's bit and clears the other candidate's;
 * a miss replaces an invalid candidate (way 1 first), else the one whose bit is clear, else
 * (both alike: the bits are shared by other pairs) way 0. The bits are flops, read in the
 * lookup clock, so a lookup sees the update of the one before.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "dark_circuit_assert.svh"

module SkewedCacheRdOnly #(
    parameter  ADDR_WIDTH  = 32,            // byte address
    parameter  SETS_WIDTH  = 6,             // 1 << SETS_WIDTH lines in each way
    parameter  SETS_OFFSET = 2,             // 1 << SETS_OFFSET bytes in a line (2: one word)
    localparam DATA_WIDTH  = 8 << SETS_OFFSET,
    localparam TAG_WIDTH   = ADDR_WIDTH - SETS_WIDTH - SETS_OFFSET,
    localparam SETS        = 1 << SETS_WIDTH
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
    `DC_STATIC_ASSERT(a_tag_covers_index, TAG_WIDTH >= SETS_WIDTH)

    typedef logic [ADDR_WIDTH-1:SETS_OFFSET] line_t;    // an address without the offset

    logic                  accept;      // a request is taken in this clock
    logic                  look;        // the request of the clock before is looked up now
    line_t                 look_line;   // its line
    logic [1:0][SETS_WIDTH-1:0] look_index;  // its index in each way
    logic [1:0][SETS_WIDTH-1:0] req_index;   // the index of the request in each way
    logic [1:0]            valid;       // of the candidates of look_line
    logic [1:0][TAG_WIDTH-1:0]  tag;
    logic [1:0][DATA_WIDTH-1:0] data;
    logic [1:0]            hits;        // one-hot: the way that hits, 0 on a miss
    logic                  hit;
    logic                  miss;
    logic                  held;        // memory does not take the miss's read: it stays
    logic                  hit_way;
    logic                  victim_way;  // the way a miss found now replaces
    logic                  fill_way;    // the way the line of the served miss goes into
    logic                  waiting;     // a miss is served: the memory has not answered yet
    logic                  refill;      // the line from memory comes: write it
    logic                  touch;       // a hit or a fill: the recent bits change
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

    // A request is taken only when nothing waits: neither a miss found now nor one served.
    assign req_ready = !waiting && !miss;
    assign accept    = req_valid && req_ready;

    always_ff @(posedge clk)
        if (!rst_n) look <= 1'b0;
        else        look <= accept || held;

    always_ff @(posedge clk)
        if (accept)
            look_line <= req_addr[ADDR_WIDTH-1:SETS_OFFSET];

    // The RAMs of each way read the request's index in that way; their answers come with
    // look. The line from memory goes into fill_way only, at look_line's index there.
    for (genvar w = 0; w < 2; w++) begin: g_way
        logic wr_en;

        assign req_index[w]  = index_of(w, req_addr[ADDR_WIDTH-1:SETS_OFFSET]);
        assign look_index[w] = index_of(w, look_line);
        assign wr_en         = refill && fill_way == 1'(w);

        CacheValidRam #(.SETS_WIDTH(SETS_WIDTH)) u_cache_valid_ram(
            .clk, .rst_n, .invalidate,
            .rd_en(accept), .rd_set(req_index[w]), .valid(valid[w]),
            .wr_en, .wr_set(look_index[w]), .wr_val(1'b1));

        CacheTagRam #(.SETS_WIDTH(SETS_WIDTH), .TAG_WIDTH(TAG_WIDTH)) u_cache_tag_ram(
            .clk,
            .rd_en(accept), .rd_set(req_index[w]), .tag(tag[w]),
            .wr_en, .wr_set(look_index[w]), .wr_tag(look_line[ADDR_WIDTH-1 -: TAG_WIDTH]));

        CacheDataRam #(.SETS_WIDTH(SETS_WIDTH), .SETS_OFFSET(SETS_OFFSET)) u_cache_data_ram(
            .clk,
            .rd_en(accept), .rd_set(req_index[w]), .data(data[w]),
            .wr_en, .wr_set(look_index[w]), .wr_data(mem_rsp_data));

        assign hits[w]        = look && valid[w] && tag[w] == look_line[ADDR_WIDTH-1 -: TAG_WIDTH];
        assign look_recent[w] = recent[w][look_index[w]];
    end

    // A line is filled only on a miss, so it is in at most one way.
    `DC_ASSERT(a_hits_onehot0, $onehot0(hits))

    assign hit     = |hits;
    assign miss    = look && !hit;
    assign hit_way = hits[1];

    // The victim of a miss: an invalid candidate (way 1 first), else the one not recently
    // used, else way 0. An assign, not always_comb (Icarus: constant selects).
    assign victim_way = !valid[1]                     ? 1'b1 :
                        !valid[0]                     ? 1'b0 :
                        look_recent[0] != look_recent[1] ? look_recent[0] :
                                                        1'b0;

    // A hit touches its way in the lookup; a fill touches fill_way when the line comes
    // (look_line stays: no request is taken meanwhile). The touched line becomes recent, the
    // other candidate not.
    assign touch     = hit || refill;
    assign touch_way = refill ? fill_way : hit_way;

    always_ff @(posedge clk)
        if (!rst_n) begin
            for (int i = 0; i < SETS; i++) begin
                recent[0][i] <= 1'b0;
                recent[1][i] <= 1'b0;
            end
        end else if (touch) begin
            recent[0][look_index[0]] <= !touch_way;
            recent[1][look_index[1]] <= touch_way;
        end

    // A miss asks memory for its line and holds the request, with its lookup, until memory
    // takes it; then the cache waits for the answer, which it passes on and writes.
    assign held = miss && !mem_req_ready;

    always_ff @(posedge clk)
        if (miss && mem_req_ready)
            fill_way <= victim_way;

    always_ff @(posedge clk)
        if (!rst_n)                     waiting <= 1'b0;
        else if (miss && mem_req_ready) waiting <= 1'b1;
        else if (mem_rsp_valid)         waiting <= 1'b0;

    // A lookup ends when memory takes its read, and no request is taken while the miss is
    // served: so the refill writes look_line's indices.
    `DC_ASSERT(a_no_look_while_waiting, !(look && waiting))

    assign refill        = waiting && mem_rsp_valid;
    assign mem_req_valid = miss;
    assign mem_req_addr  = {look_line, {SETS_OFFSET{1'b0}}};
    assign rsp_valid     = hit || refill;
    assign rsp_data      = waiting ? mem_rsp_data : (hit_way ? data[1] : data[0]);

endmodule

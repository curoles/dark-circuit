/* Set-associative read-only cache (an instruction cache), made of blocks and gates.
 *
 * Same ports and behavior as the behave version (see there, and DirectCacheRdOnly for the
 * protocol). Per way the struct CacheValidRam, CacheTagRam and CacheDataRam, a CmpEq of the
 * tag and And3 for its hit; their write enables come from a Decoder of fill_way (enabled by
 * refill). Control as in the struct DirectCacheRdOnly, plus:
 *   hit      = OrReduce(hits)                hit_way = PriorityEncoder(hits), hits one-hot
 *   hit_data = per bit OrReduce over the ways of (line AND hit of the way)
 *   fill_way = Dff with a hold Mux2 (miss) of CacheReplacement's victim_way
 *   touch    = hit OR refill                 touch_way = Mux2(hit_way, fill_way, refill)
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
    input  wire                  req_en,
    // The offset in the line is not used: the cache answers whole lines.
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire [ADDR_WIDTH-1:0] req_addr,
    /* verilator lint_on UNUSEDSIGNAL */
    output wire                  req_ready,     // 0 while a miss is served: hold the request
    output wire                  rsp_valid,     // rsp_data is the line asked for
    output wire [DATA_WIDTH-1:0] rsp_data,

    // Memory side
    output wire                  mem_req_en,
    output wire [ADDR_WIDTH-1:0] mem_req_addr,  // address of the line (offset 0)
    input  wire                  mem_rsp_valid,
    input  wire [DATA_WIDTH-1:0] mem_rsp_data
);
    localparam LINE_WIDTH = ADDR_WIDTH - SETS_OFFSET;   // address bits above the offset
    localparam WAYS_POW2  = 1 << WAY_WIDTH;             // ways rounded up to a power of 2

    wire                  accept;       // a request is taken in this clock
    wire                  look;         // the request of the clock before is looked up now
    wire [LINE_WIDTH-1:0] look_line;    // its address without the offset in the line
    wire [LINE_WIDTH-1:0] look_line_next;
    wire [WAYS-1:0]       valid;        // of the ways of the set of look_line
    wire [WAYS-1:0]       hits;         // one-hot: the way that hits, 0 on a miss
    wire                  hit;
    wire                  hit_n;
    wire                  miss;
    // Bits no way reaches when WAYS is not a power of 2; valid of the encoder (hit says it).
    /* verilator lint_off UNUSEDSIGNAL */
    wire [WAYS_POW2-1:0]  way_wr_en;    // one-hot: the way refill writes
    wire                  hit_way_valid;
    /* verilator lint_on UNUSEDSIGNAL */
    wire [WAYS_POW2-1:0]  hits_pow2;    // hits, padded with 0 for PriorityEncoder
    wire [WAY_WIDTH-1:0]  hit_way;
    wire [WAYS-1:0][DATA_WIDTH-1:0] line_masked;    // line of each way if it hits, else 0
    wire [DATA_WIDTH-1:0] hit_data;
    wire [WAY_WIDTH-1:0]  victim_way;   // CacheReplacement's way for a miss found now
    wire [WAY_WIDTH-1:0]  fill_way;     // the way the line of the served miss goes into
    wire [WAY_WIDTH-1:0]  fill_way_next;
    wire                  touch;
    wire [WAY_WIDTH-1:0]  touch_way;
    wire                  waiting;      // a miss is served: the memory has not answered yet
    wire                  waiting_next;
    wire                  waiting_kept; // waiting, and the memory does not answer now
    wire                  mem_rsp_n;
    wire                  refill;       // the line from memory comes: write it

    Nor2 #(1) u_nor2_ready (.in1(waiting), .in2(miss), .out(req_ready));
    And2 #(1) u_and2_accept(.in1(req_en), .in2(req_ready), .out(accept));

    DffSyncRst #(.WIDTH(1)) u_dff_sync_rst_look(.clk, .rst_n, .in(accept), .out(look));
    Mux2 #(LINE_WIDTH) u_mux2_line(.in0(look_line), .in1(req_addr[ADDR_WIDTH-1:SETS_OFFSET]),
                                   .sel(accept), .out(look_line_next));
    Dff  #(LINE_WIDTH) u_dff_line (.clk, .in(look_line_next), .out(look_line));

    Decoder #(.SIZE(WAY_WIDTH)) u_decoder_fill(.in(fill_way), .en(refill), .out(way_wr_en));

    for (genvar w = 0; w < WAYS; w++) begin: g_way
        wire [TAG_WIDTH-1:0]  tag;
        wire [DATA_WIDTH-1:0] data;
        wire                  tag_eq;

        CacheValidRam #(.SETS_WIDTH(SETS_WIDTH)) u_cache_valid_ram(
            .clk, .rst_n, .invalidate,
            .rd_en(accept), .rd_set(req_addr[SETS_OFFSET +: SETS_WIDTH]), .valid(valid[w]),
            .wr_en(way_wr_en[w]), .wr_set(look_line[SETS_WIDTH-1:0]), .wr_val(1'b1));

        CacheTagRam #(.SETS_WIDTH(SETS_WIDTH), .TAG_WIDTH(TAG_WIDTH)) u_cache_tag_ram(
            .clk,
            .rd_en(accept), .rd_set(req_addr[SETS_OFFSET +: SETS_WIDTH]), .tag,
            .wr_en(way_wr_en[w]), .wr_set(look_line[SETS_WIDTH-1:0]),
            .wr_tag(look_line[LINE_WIDTH-1:SETS_WIDTH]));

        CacheDataRam #(.SETS_WIDTH(SETS_WIDTH), .SETS_OFFSET(SETS_OFFSET)) u_cache_data_ram(
            .clk,
            .rd_en(accept), .rd_set(req_addr[SETS_OFFSET +: SETS_WIDTH]), .data,
            .wr_en(way_wr_en[w]), .wr_set(look_line[SETS_WIDTH-1:0]), .wr_data(mem_rsp_data));

        CmpEq #(TAG_WIDTH) u_cmp_eq(.in1(tag), .in2(look_line[LINE_WIDTH-1:SETS_WIDTH]),
                                    .eq(tag_eq));
        And3  #(1) u_and3_hit(.in1(look), .in2(valid[w]), .in3(tag_eq), .out(hits[w]));
        And2  #(DATA_WIDTH) u_and2_line(.in1(data), .in2({DATA_WIDTH{hits[w]}}),
                                        .out(line_masked[w]));
    end

    // A line is filled only on a miss, so a tag is in at most one way of a set.
    `DC_ASSERT(a_hits_onehot0, $onehot0(hits))

    OrReduce #(WAYS) u_or_reduce_hit(.in(hits), .out(hit));
    Inv      #(1)    u_inv_hit (.in(hit), .out(hit_n));
    And2     #(1)    u_and2_miss(.in1(look), .in2(hit_n), .out(miss));

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
        OrReduce #(WAYS) u_or_reduce_data(.in(ways_bit), .out(hit_data[b]));
    end

    // The replacement state is read with the request; a hit touches its way, a fill
    // fill_way.
    Or2  #(1)         u_or2_touch      (.in1(hit), .in2(refill), .out(touch));
    Mux2 #(WAY_WIDTH) u_mux2_touch_way (.in0(hit_way), .in1(fill_way), .sel(refill),
                                        .out(touch_way));
    CacheReplacement #(.WAYS(WAYS), .SETS_WIDTH(SETS_WIDTH), .POLICY(REPLACEMENT))
        u_cache_replacement(
            .clk, .rst_n,
            .rd_en(accept), .rd_set(req_addr[SETS_OFFSET +: SETS_WIDTH]),
            .touch, .touch_way, .valid, .victim_way);

    // The victim is taken in the clock the miss is found: the random way changes every clock.
    Mux2 #(WAY_WIDTH) u_mux2_fill(.in0(fill_way), .in1(victim_way), .sel(miss),
                                  .out(fill_way_next));
    Dff  #(WAY_WIDTH) u_dff_fill (.clk, .in(fill_way_next), .out(fill_way));

    Inv  #(1) u_inv_rsp   (.in(mem_rsp_valid), .out(mem_rsp_n));
    And2 #(1) u_and2_kept (.in1(waiting), .in2(mem_rsp_n), .out(waiting_kept));
    Or2  #(1) u_or2_wait  (.in1(miss), .in2(waiting_kept), .out(waiting_next));
    DffSyncRst #(.WIDTH(1)) u_dff_sync_rst_wait(.clk, .rst_n, .in(waiting_next), .out(waiting));

    And2 #(1)          u_and2_refill(.in1(waiting), .in2(mem_rsp_valid), .out(refill));
    Or2  #(1)          u_or2_rsp    (.in1(hit), .in2(refill), .out(rsp_valid));
    Mux2 #(DATA_WIDTH) u_mux2_data  (.in0(hit_data), .in1(mem_rsp_data), .sel(waiting),
                                     .out(rsp_data));

    assign mem_req_en   = miss;
    assign mem_req_addr = {look_line, {SETS_OFFSET{1'b0}}};

endmodule

/* Set-associative read-write cache (a data cache), write-through, made of blocks and gates.
 *
 * Same ports, parameters and behavior as the behave version (see there, and DirectCache for
 * the protocol, the write policy and forwarding). Per way the struct CacheValidRam,
 * CacheTagRam and CacheDataRam, a CmpEq of the tag and And3 for its hit. The request taken
 * is a DffEn (accept) for the line address and, unless READ_ONLY, one for the fields of a
 * store (we, wdata, wstrb). Control as in the struct DirectCache (READ_ONLY=1: the same logic
 * left out), plus:
 *   hit      = OrReduce(hits)                hit_way = PriorityEncoder(hits), hits one-hot
 *   hit_line = per bit OrReduce over the ways of (line AND hit of the way)
 *   fill_way = DffEn (load_miss AND mem_req_ready) of CacheReplacement's victim_way
 *   touch    = load_hit OR store_write OR refill    touch_way = Mux2(hit_way, fill_way, refill)
 * and per way w:
 *   valid and tag RAM write: refill AND fill_way == w (a Decoder of fill_way)
 *   data RAM write: that OR (store_write AND hits[w]), Mux2(merged, mem_rsp_data, refill)
 *   line[w]  = Mux2(ram_line[w], fwd_line, fwd AND fwd_hits[w]), where fwd_hits is a DffEn
 *              (store_write) of hits: the way of the store, one-hot
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
    localparam LINE_WIDTH = ADDR_WIDTH - SETS_OFFSET;   // address bits above the offset
    localparam STORE_WIDTH = 1 + DATA_WIDTH + STRB_WIDTH;   // the fields of a store kept
    localparam WAYS_POW2  = 1 << WAY_WIDTH;             // ways rounded up to a power of 2

    wire                  accept;       // a request is taken in this clock
    wire                  look;         // a request taken before is looked up now (or held)
    wire                  look_next;
    wire [LINE_WIDTH-1:0] look_line;    // its address without the offset in the line
    wire                  look_we;
    wire                  look_we_n;
    wire [DATA_WIDTH-1:0] look_wdata;
    wire [STRB_WIDTH-1:0] look_wstrb;
    wire [WAYS-1:0]       valid;        // of the ways of the set of look_line
    wire [WAYS-1:0]       hits;         // one-hot: the way that hits, 0 on a miss
    wire                  hit;
    wire                  hit_n;
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
    wire                  store;        // a store is looked up
    wire                  load;         // a load is looked up
    wire                  load_hit;
    wire                  load_miss;
    wire                  mem_ready_n;
    wire                  held;         // its memory request is not taken: the lookup stays
    wire                  store_write;  // a store that hits is taken by memory: write merged
    wire                  waiting;      // a load miss is served: memory has not answered yet
    wire                  waiting_next;
    wire                  wait_start;   // memory takes the read of a load miss
    wire                  waiting_kept; // waiting, and memory does not answer now
    wire                  mem_rsp_n;
    wire                  refill;       // the line from memory comes: write it
    wire [DATA_WIDTH-1:0] ram_wr_line;  // what a data RAM write writes: the fill or merged
    wire [WAY_WIDTH-1:0]  victim_way;   // CacheReplacement's way for a load miss found now
    wire [WAY_WIDTH-1:0]  fill_way;     // the way the line of the served miss goes into
    wire                  touch;
    wire [WAY_WIDTH-1:0]  touch_way;

    Nor3 #(1) u_nor3_ready (.in1(waiting), .in2(load_miss), .in3(held), .out(req_ready));
    And2 #(1) u_and2_accept(.in1(req_valid), .in2(req_ready), .out(accept));

    Or2 #(1) u_or2_look(.in1(accept), .in2(held), .out(look_next));
    DffSyncRst #(.WIDTH(1)) u_dff_sync_rst_look(.clk, .rst_n, .in(look_next), .out(look));

    // The line address of the request taken, kept for its lookup.
    DffEn #(LINE_WIDTH) u_dff_en_line(.clk, .en(accept), .in(req_addr[ADDR_WIDTH-1:SETS_OFFSET]),
                                      .out(look_line));

    Decoder #(.SIZE(WAY_WIDTH)) u_decoder_fill(.in(fill_way), .en(refill), .out(fill_wr));

    for (genvar w = 0; w < WAYS; w++) begin: g_way
        wire [TAG_WIDTH-1:0]  tag;
        wire                  tag_eq;
        wire                  store_wr;     // a store's merged line writes this way
        wire                  data_wr;

        CacheValidRam #(.SETS_WIDTH(SETS_WIDTH)) u_cache_valid_ram(
            .clk, .rst_n, .invalidate,
            .rd_en(accept), .rd_set(req_addr[SETS_OFFSET +: SETS_WIDTH]), .valid(valid[w]),
            .wr_en(fill_wr[w]), .wr_set(look_line[SETS_WIDTH-1:0]), .wr_val(1'b1));

        CacheTagRam #(.SETS_WIDTH(SETS_WIDTH), .TAG_WIDTH(TAG_WIDTH)) u_cache_tag_ram(
            .clk,
            .rd_en(accept), .rd_set(req_addr[SETS_OFFSET +: SETS_WIDTH]), .tag,
            .wr_en(fill_wr[w]), .wr_set(look_line[SETS_WIDTH-1:0]),
            .wr_tag(look_line[LINE_WIDTH-1:SETS_WIDTH]));

        And2 #(1) u_and2_store_wr(.in1(store_write), .in2(hits[w]), .out(store_wr));
        Or2  #(1) u_or2_data_wr  (.in1(fill_wr[w]), .in2(store_wr), .out(data_wr));
        CacheDataRam #(.SETS_WIDTH(SETS_WIDTH), .SETS_OFFSET(SETS_OFFSET)) u_cache_data_ram(
            .clk,
            .rd_en(accept), .rd_set(req_addr[SETS_OFFSET +: SETS_WIDTH]), .data(ram_line[w]),
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

    // Lookup.
    Inv  #(1) u_inv_hit       (.in(hit), .out(hit_n));
    Inv  #(1) u_inv_we        (.in(look_we), .out(look_we_n));
    And2 #(1) u_and2_store    (.in1(look), .in2(look_we), .out(store));
    And2 #(1) u_and2_load     (.in1(look), .in2(look_we_n), .out(load));
    And2 #(1) u_and2_load_hit (.in1(load), .in2(hit), .out(load_hit));
    And2 #(1) u_and2_load_miss(.in1(load), .in2(hit_n), .out(load_miss));

    // Memory request: a store always, a load when it misses (from the lookup's registers).
    Or2  #(1) u_or2_mem_valid(.in1(store), .in2(load_miss), .out(mem_req_valid));
    Inv  #(1) u_inv_mem_ready(.in(mem_req_ready), .out(mem_ready_n));
    And2 #(1) u_and2_held    (.in1(mem_req_valid), .in2(mem_ready_n), .out(held));
    assign mem_req_we    = look_we;
    assign mem_req_addr  = {look_line, {SETS_OFFSET{1'b0}}};
    assign mem_req_wdata = look_wdata;
    assign mem_req_wstrb = look_wstrb;

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
        wire [STORE_WIDTH-1:0] look_store;      // {we, wdata, wstrb} of the lookup
        wire [DATA_WIDTH-1:0]  merged;          // hit_line with the bytes of the store
        wire                   same_set;        // the request taken is of the lookup's set
        wire                   fwd_new;         // the request taken at a store's write, same set
        wire                   fwd;             // a RAM line is older than a store's write
        wire [WAYS-1:0]        fwd_hits;        // one-hot: the way of that store
        wire [DATA_WIDTH-1:0]  fwd_line;

        // The fields of the store taken, kept for its lookup.
        DffEn #(STORE_WIDTH) u_dff_en_store(.clk, .en(accept), .in({req_we, req_wdata, req_wstrb}),
                                            .out(look_store));
        assign {look_we, look_wdata, look_wstrb} = look_store;

        // Store: the bytes of its strobes into the line, written when memory takes the store.
        for (genvar b = 0; b < STRB_WIDTH; b++) begin: g_byte
            Mux2 #(8) u_mux2_byte(.in0(hit_line[8*b +: 8]), .in1(look_wdata[8*b +: 8]),
                                  .sel(look_wstrb[b]), .out(merged[8*b +: 8]));
        end
        And3 #(1) u_and3_store_write(.in1(store), .in2(hit), .in3(mem_req_ready),
                                     .out(store_write));
        Mux2 #(DATA_WIDTH) u_mux2_ram_wr(.in0(merged), .in1(mem_rsp_data), .sel(refill),
                                         .out(ram_wr_line));

        // Forwarding (see the behave version): decided at the edge of a read; the line and
        // the way of the store kept at its write.
        CmpEq #(SETS_WIDTH) u_cmp_eq_set(.in1(look_line[SETS_WIDTH-1:0]),
                                         .in2(req_addr[SETS_OFFSET +: SETS_WIDTH]),
                                         .eq(same_set));
        And2  #(1) u_and2_fwd (.in1(store_write), .in2(same_set), .out(fwd_new));
        DffSyncRstEn #(.WIDTH(1)) u_dff_sync_rst_en_fwd(.clk, .rst_n, .en(accept), .in(fwd_new),
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
            .rd_en(accept), .rd_set(req_addr[SETS_OFFSET +: SETS_WIDTH]),
            .touch, .touch_way, .valid, .victim_way);

    // Load miss served from the clock memory takes its read until the answer comes; the
    // victim is taken then: the random way changes every clock, also while the miss is held.
    And2 #(1) u_and2_wait_start(.in1(load_miss), .in2(mem_req_ready), .out(wait_start));
    DffEn #(WAY_WIDTH) u_dff_en_fill(.clk, .en(wait_start), .in(victim_way), .out(fill_way));
    Inv  #(1) u_inv_rsp        (.in(mem_rsp_valid), .out(mem_rsp_n));
    And2 #(1) u_and2_kept      (.in1(waiting), .in2(mem_rsp_n), .out(waiting_kept));
    Or2  #(1) u_or2_wait       (.in1(wait_start), .in2(waiting_kept), .out(waiting_next));
    DffSyncRst #(.WIDTH(1)) u_dff_sync_rst_wait(.clk, .rst_n, .in(waiting_next), .out(waiting));
    And2 #(1) u_and2_refill    (.in1(waiting), .in2(mem_rsp_valid), .out(refill));

    // See the behave version.
    `DC_ASSERT(a_no_look_while_waiting, !(look && waiting))

    Or2  #(1)          u_or2_rsp  (.in1(load_hit), .in2(refill), .out(rsp_valid));
    Mux2 #(DATA_WIDTH) u_mux2_data(.in0(hit_line), .in1(mem_rsp_data), .sel(waiting),
                                   .out(rsp_data));

endmodule

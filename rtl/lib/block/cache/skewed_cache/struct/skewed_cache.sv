/* Two-way skewed-associative read-write cache (a data cache), write-through, made of blocks
 * and gates.
 *
 * Same ports, parameters and behavior as the behave version (see there, and DirectCache for
 * the protocol, the write policy and forwarding). Per way the struct CacheValidRam,
 * CacheTagRam and CacheDataRam at the way's index (way 1: an Xor2 of the set and the low bits
 * of the tag, for the request and for the line looked up), a CmpEq of the tag and And3 for
 * its hit. The request taken is a Dff with a hold Mux2 (accept) for the line address and,
 * unless READ_ONLY, one for the fields of a store (we, wdata, wstrb). Control as in the
 * struct SetAssocCache (READ_ONLY=1: the same logic left out), plus:
 *   hit_way    = hits[1]                   hit_line = Mux2(line[0], line[1], hits[1])
 *   victim_way = ~valid[1] | (valid[0] & recent[0] & ~recent[1])
 *   recent     = per way a RegFile of one bit per line (read combinationally at the line
 *                looked up; written on touch: !touch_way in way 0, touch_way in way 1)
 * and per way w:
 *   valid and tag RAM write: refill AND fill_way == w
 *   data RAM write: that OR (store_write AND hits[w]), Mux2(merged, mem_rsp_data, refill)
 *   fwd[w]  = DffSyncRst(accept ? store_write AND hits[w] AND (index of the lookup in w ==
 *             index of the request in w) : fwd[w])
 *   line[w] = Mux2(ram_line[w], fwd_line, fwd[w])
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
    localparam TAG_WIDTH   = ADDR_WIDTH - SETS_WIDTH - SETS_OFFSET
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

    localparam LINE_WIDTH = ADDR_WIDTH - SETS_OFFSET;   // address bits above the offset
    localparam STORE_WIDTH = 1 + DATA_WIDTH + STRB_WIDTH;   // the fields of a store kept

    wire                  accept;       // a request is taken in this clock
    wire                  look;         // a request taken before is looked up now (or held)
    wire                  look_next;
    wire [LINE_WIDTH-1:0] req_line;     // the request's address without the offset
    wire [LINE_WIDTH-1:0] look_line;    // its address without the offset in the line
    wire [LINE_WIDTH-1:0] look_line_next;
    wire                  look_we;
    wire                  look_we_n;
    wire [DATA_WIDTH-1:0] look_wdata;
    wire [STRB_WIDTH-1:0] look_wstrb;
    wire [1:0][SETS_WIDTH-1:0] req_index;   // the request's index in each way
    wire [1:0][SETS_WIDTH-1:0] look_index;  // look_line's index in each way
    wire [1:0]            valid;        // of the candidates of look_line
    wire [1:0]            hits;         // one-hot: the way that hits, 0 on a miss
    wire [1:0][DATA_WIDTH-1:0] ram_line;    // line of each candidate as its RAM read it
    wire [1:0][DATA_WIDTH-1:0] line;    // line of each candidate now: forwarded or RAM
    wire [1:0]            fill_wr;      // refill writes the way
    wire [1:0]            recent;       // the recent bits of the candidates of look_line
    wire [1:0]            recent_new;   // their new values on a touch
    wire                  hit;
    wire                  hit_n;
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
    wire                  valid1_n;
    wire                  recent1_n;
    wire                  pick_older;   // both valid, way 0 recent and way 1 not: way 1
    wire                  victim_way;   // the way a load miss found now replaces
    wire                  fill_way;     // the way the line of the served miss goes into
    wire                  fill_way_n;
    wire                  fill_way_next;
    wire                  touch;
    wire                  touch_way;
    wire                  touch_way_n;

    Nor3 #(1) u_nor3_ready (.in1(waiting), .in2(load_miss), .in3(held), .out(req_ready));
    And2 #(1) u_and2_accept(.in1(req_valid), .in2(req_ready), .out(accept));

    Or2 #(1) u_or2_look(.in1(accept), .in2(held), .out(look_next));
    DffSyncRst #(.WIDTH(1)) u_dff_sync_rst_look(.clk, .rst_n, .in(look_next), .out(look));

    // The line address of the request taken, kept for its lookup.
    assign req_line = req_addr[ADDR_WIDTH-1:SETS_OFFSET];
    Mux2 #(LINE_WIDTH) u_mux2_line(.in0(look_line), .in1(req_line), .sel(accept),
                                   .out(look_line_next));
    Dff  #(LINE_WIDTH) u_dff_line (.clk, .in(look_line_next), .out(look_line));

    // @kb: rtl/lib/block/cache/skewed_cache_rd_only/design
    // The indices: way 0 the set, way 1 the set xor the low bits of the tag.
    assign req_index[0]  = req_line[SETS_WIDTH-1:0];
    assign look_index[0] = look_line[SETS_WIDTH-1:0];
    Xor2 #(SETS_WIDTH) u_xor2_req_index (.in1(req_line[SETS_WIDTH-1:0]),
                                         .in2(req_line[2*SETS_WIDTH-1:SETS_WIDTH]),
                                         .out(req_index[1]));
    Xor2 #(SETS_WIDTH) u_xor2_look_index(.in1(look_line[SETS_WIDTH-1:0]),
                                         .in2(look_line[2*SETS_WIDTH-1:SETS_WIDTH]),
                                         .out(look_index[1]));

    // The way refill writes.
    Inv  #(1) u_inv_fill  (.in(fill_way), .out(fill_way_n));
    And2 #(1) u_and2_wr_0 (.in1(refill), .in2(fill_way_n), .out(fill_wr[0]));
    And2 #(1) u_and2_wr_1 (.in1(refill), .in2(fill_way), .out(fill_wr[1]));

    // A touch makes its line recent and the other candidate not: the new bit of each way (a
    // vector, not (w == 0) ? ... in the port: Icarus makes that X).
    Inv  #(1) u_inv_touch (.in(touch_way), .out(touch_way_n));
    assign recent_new = {touch_way, touch_way_n};

    for (genvar w = 0; w < 2; w++) begin: g_way
        wire [TAG_WIDTH-1:0]  tag;
        wire                  tag_eq;
        wire                  store_wr;     // a store's merged line writes this way
        wire                  data_wr;

        CacheValidRam #(.SETS_WIDTH(SETS_WIDTH)) u_cache_valid_ram(
            .clk, .rst_n, .invalidate,
            .rd_en(accept), .rd_set(req_index[w]), .valid(valid[w]),
            .wr_en(fill_wr[w]), .wr_set(look_index[w]), .wr_val(1'b1));

        CacheTagRam #(.SETS_WIDTH(SETS_WIDTH), .TAG_WIDTH(TAG_WIDTH)) u_cache_tag_ram(
            .clk,
            .rd_en(accept), .rd_set(req_index[w]), .tag,
            .wr_en(fill_wr[w]), .wr_set(look_index[w]),
            .wr_tag(look_line[LINE_WIDTH-1:SETS_WIDTH]));

        And2 #(1) u_and2_store_wr(.in1(store_write), .in2(hits[w]), .out(store_wr));
        Or2  #(1) u_or2_data_wr  (.in1(fill_wr[w]), .in2(store_wr), .out(data_wr));
        CacheDataRam #(.SETS_WIDTH(SETS_WIDTH), .SETS_OFFSET(SETS_OFFSET)) u_cache_data_ram(
            .clk,
            .rd_en(accept), .rd_set(req_index[w]), .data(ram_line[w]),
            .wr_en(data_wr), .wr_set(look_index[w]), .wr_data(ram_wr_line));

        CmpEq #(TAG_WIDTH) u_cmp_eq(.in1(tag), .in2(look_line[LINE_WIDTH-1:SETS_WIDTH]),
                                    .eq(tag_eq));
        And3  #(1) u_and3_hit(.in1(look), .in2(valid[w]), .in3(tag_eq), .out(hits[w]));

        // The recent bits of the way: written by the fill that makes a line valid, read only
        // when both candidates are valid, so no reset.
        RegFile #(.RD_PORTS(1), .WR_PORTS(1), .ADDR_WIDTH(SETS_WIDTH), .DATA_WIDTH(1))
            u_reg_file_recent(
                .clk, .rd_addr(look_index[w]), .rd_data(recent[w]),
                .wr_en(touch), .wr_addr(look_index[w]), .wr_data(recent_new[w]));
    end

    // A line is filled only on a miss, so it is in at most one way.
    `DC_ASSERT(a_hits_onehot0, $onehot0(hits))

    Or2  #(1) u_or2_hit(.in1(hits[0]), .in2(hits[1]), .out(hit));
    Mux2 #(DATA_WIDTH) u_mux2_hit_line(.in0(line[0]), .in1(line[1]), .sel(hits[1]),
                                       .out(hit_line));

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
        wire [STORE_WIDTH-1:0] look_store_next;
        wire [DATA_WIDTH-1:0]  merged;          // hit_line with the bytes of the store
        wire [DATA_WIDTH-1:0]  fwd_line;
        wire [DATA_WIDTH-1:0]  fwd_line_next;

        // The fields of the store taken, kept for its lookup.
        Mux2 #(STORE_WIDTH) u_mux2_store(.in0(look_store), .in1({req_we, req_wdata, req_wstrb}),
                                         .sel(accept), .out(look_store_next));
        Dff  #(STORE_WIDTH) u_dff_store (.clk, .in(look_store_next), .out(look_store));
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
        Mux2 #(DATA_WIDTH) u_mux2_fwd_line(.in0(fwd_line), .in1(merged), .sel(store_write),
                                           .out(fwd_line_next));
        Dff  #(DATA_WIDTH) u_dff_fwd_line (.clk, .in(fwd_line_next), .out(fwd_line));

        for (genvar w = 0; w < 2; w++) begin: g_line
            wire same_index;   // the request taken has the lookup's index here
            wire fwd_new;      // the request taken at a store's write here
            wire fwd;          // this way's RAM read a line older than a store
            wire fwd_next;

            // Forwarding (see the behave version): decided at the edge of a read, per way.
            // @kb: rtl/lib/block/cache/skewed_cache/design
            CmpEq #(SETS_WIDTH) u_cmp_eq_index(.in1(look_index[w]), .in2(req_index[w]),
                                               .eq(same_index));
            And3  #(1) u_and3_fwd(.in1(store_write), .in2(hits[w]), .in3(same_index),
                                  .out(fwd_new));
            Mux2  #(1) u_mux2_fwd(.in0(fwd), .in1(fwd_new), .sel(accept), .out(fwd_next));
            DffSyncRst #(.WIDTH(1)) u_dff_sync_rst_fwd(.clk, .rst_n, .in(fwd_next), .out(fwd));
            Mux2 #(DATA_WIDTH) u_mux2_line(.in0(ram_line[w]), .in1(fwd_line), .sel(fwd),
                                           .out(line[w]));
        end
    end

    // The victim: an invalid candidate (way 1 first), else the one not recently used, else
    // way 0: ~valid[1] | (valid[0] & recent[0] & ~recent[1]).
    Inv  #(1) u_inv_valid1 (.in(valid[1]), .out(valid1_n));
    Inv  #(1) u_inv_recent1(.in(recent[1]), .out(recent1_n));
    And3 #(1) u_and3_older (.in1(valid[0]), .in2(recent[0]), .in3(recent1_n), .out(pick_older));
    Or2  #(1) u_or2_victim (.in1(valid1_n), .in2(pick_older), .out(victim_way));

    // A load hit touches its line in the lookup, a store hit when memory takes it, a fill
    // fill_way when the line comes.
    Or3  #(1) u_or3_touch     (.in1(load_hit), .in2(store_write), .in3(refill), .out(touch));
    Mux2 #(1) u_mux2_touch_way(.in0(hits[1]), .in1(fill_way), .sel(refill), .out(touch_way));

    // Load miss served from the clock memory takes its read until the answer comes; the
    // victim is taken then.
    And2 #(1) u_and2_wait_start(.in1(load_miss), .in2(mem_req_ready), .out(wait_start));
    Mux2 #(1) u_mux2_fill(.in0(fill_way), .in1(victim_way), .sel(wait_start),
                          .out(fill_way_next));
    Dff  #(1) u_dff_fill (.clk, .in(fill_way_next), .out(fill_way));
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

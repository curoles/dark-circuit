/* Two-way skewed-associative read-write cache (a data cache), write-through, made of blocks
 * and gates.
 *
 * Same ports, parameters and behavior as the behave version (see there; the protocol, the
 * write policy, uncached requests and READ_ONLY are CacheControl's). Per way the struct
 * CacheValidRam, CacheTagRam and CacheDataRam at the way's index (way 1: an Xor2 of the set
 * and the low bits of the tag, for the request and for the line looked up), a CmpEq of the
 * tag and And3 for its hit. Then:
 *   hit_way    = hits[1]                   hit_line = Mux2(line[0], line[1], hits[1])
 *   victim_way = ~valid[1] | (valid[0] & recent[0] & ~recent[1])
 *   recent     = per way a RegFile of one bit per line (read combinationally at the line
 *                looked up; written on touch: !touch_way in way 0, touch_way in way 1)
 * and per way w:
 *   valid and tag RAM write: refill AND fill_way == w
 *   data RAM write: that OR (store_write AND hits[w]), of CacheControl's ram_wr_line
 *   fwd[w]  = DffSyncRstEn(en ram_rd) of store_write AND hits[w] AND (index of the lookup
 *             in w == index of the request in w)
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
    input  wire                  mem_rsp_valid,
    input  wire [DATA_WIDTH-1:0] mem_rsp_data
);
    `DC_STATIC_ASSERT(a_tag_covers_index, TAG_WIDTH >= SETS_WIDTH)

    localparam LINE_WIDTH = ADDR_WIDTH - SETS_OFFSET;   // address bits above the offset

    wire                  ram_rd;       // the RAMs read: a request taken, or a replay
    wire                  replay;       // the lookup reads its RAMs again (CacheControl)
    wire                  look;         // a request taken before is looked up now (or held)
    wire [2*SETS_WIDTH-1:0] req_low;    // the request's set and the low bits of its tag
    wire [LINE_WIDTH-1:0] look_line;    // the lookup's address without the offset in the line
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
    wire [DATA_WIDTH-1:0] hit_line;     // the line of the way that hits
    wire                  load_hit;
    wire                  store_write;  // a store that hits is taken by memory: write merged
    wire                  refill;       // the line from memory comes: write it
    wire                  miss_taken;   // memory takes the read of a load miss
    wire [1:0]            same_index;   // per way: the request has look_line's index there
    wire                  fill_conflict;    // the request is at the place the refill writes
    wire [DATA_WIDTH-1:0] ram_wr_line;  // what a data RAM write writes: the fill or merged
    // The hit line with the store's bytes: only forwarding reads it (none when READ_ONLY).
    /* verilator lint_off UNUSEDSIGNAL */
    wire [DATA_WIDTH-1:0] merged;
    /* verilator lint_on UNUSEDSIGNAL */
    wire                  valid1_n;
    wire                  recent1_n;
    wire                  pick_older;   // both valid, way 0 recent and way 1 not: way 1
    wire                  victim_way;   // the way a load miss found now replaces
    wire                  fill_way;     // the way the line of the served miss goes into
    wire                  fill_way_n;
    wire                  touch;
    wire                  touch_way;
    wire                  touch_way_n;

    CacheControl #(.ADDR_WIDTH(ADDR_WIDTH), .SETS_OFFSET(SETS_OFFSET), .READ_ONLY(READ_ONLY))
        u_control(
            .clk, .rst_n,
            .req_valid, .req_ready, .req_uncached_dbg_bypass,
            .req_we, .req_addr, .req_wdata, .req_wstrb,
            .req_size, .req_nocache, .rsp_valid, .rsp_data,
            .mem_req_valid, .mem_req_ready, .mem_req_we, .mem_req_addr, .mem_req_wdata,
            .mem_req_wstrb, .mem_req_size, .mem_rsp_valid, .mem_rsp_data,
            .ram_rd, .look, .look_line, .load_hit, .store_write, .refill, .miss_taken,
            .replay, .ram_wr_line, .merged, .hit, .hit_line, .fill_conflict);

    assign req_low = req_addr[SETS_OFFSET +: 2*SETS_WIDTH];

    // @kb: rtl/lib/block/cache/skewed_cache_rd_only/design
    // The indices: way 0 the set, way 1 the set xor the low bits of the tag.
    assign req_index[0]  = req_low[SETS_WIDTH-1:0];
    assign look_index[0] = look_line[SETS_WIDTH-1:0];
    Xor2 #(SETS_WIDTH) u_xor2_req_index (.in1(req_low[SETS_WIDTH-1:0]),
                                         .in2(req_low[2*SETS_WIDTH-1:SETS_WIDTH]),
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
        wire [SETS_WIDTH-1:0] rd_index;     // the RAMs read it: req_index, look_index on a replay

        Mux2 #(SETS_WIDTH) u_mux2_rd_index(.in0(req_index[w]), .in1(look_index[w]), .sel(replay),
                                           .out(rd_index));

        CacheValidRam #(.SETS_WIDTH(SETS_WIDTH)) u_cache_valid_ram(
            .clk, .rst_n, .invalidate,
            .rd_en(ram_rd), .rd_set(rd_index), .valid(valid[w]),
            .wr_en(fill_wr[w]), .wr_set(look_index[w]), .wr_val(1'b1));

        CacheTagRam #(.SETS_WIDTH(SETS_WIDTH), .TAG_WIDTH(TAG_WIDTH)) u_cache_tag_ram(
            .clk,
            .rd_en(ram_rd), .rd_set(rd_index), .tag,
            .wr_en(fill_wr[w]), .wr_set(look_index[w]),
            .wr_tag(look_line[LINE_WIDTH-1:SETS_WIDTH]));

        And2 #(1) u_and2_store_wr(.in1(store_write), .in2(hits[w]), .out(store_wr));
        Or2  #(1) u_or2_data_wr  (.in1(fill_wr[w]), .in2(store_wr), .out(data_wr));
        CacheDataRam #(.SETS_WIDTH(SETS_WIDTH), .SETS_OFFSET(SETS_OFFSET)) u_cache_data_ram(
            .clk,
            .rd_en(ram_rd), .rd_set(rd_index), .data(ram_line[w]),
            .wr_en(data_wr), .wr_set(look_index[w]), .wr_data(ram_wr_line));

        CmpEq #(TAG_WIDTH) u_cmp_eq(.in1(tag), .in2(look_line[LINE_WIDTH-1:SETS_WIDTH]),
                                    .eq(tag_eq));
        And3  #(1) u_and3_hit(.in1(look), .in2(valid[w]), .in3(tag_eq), .out(hits[w]));
        CmpEq #(SETS_WIDTH) u_cmp_eq_index(.in1(look_index[w]), .in2(req_index[w]),
                                           .eq(same_index[w]));

        // The recent bits of the way: written by the fill that makes a line valid, read only
        // when both candidates are valid, so no reset.
        RegFile #(.RD_PORTS(1), .WR_PORTS(1), .ADDR_WIDTH(SETS_WIDTH), .DATA_WIDTH(1))
            u_reg_file_recent(
                .clk, .rd_addr(look_index[w]), .rd_data(recent[w]),
                .wr_en(touch), .wr_addr(look_index[w]), .wr_data(recent_new[w]));
    end

    // A line is filled only on a miss, so it is in at most one way.
    `DC_ASSERT(a_hits_onehot0, $onehot0(hits))

    // The request is at the place the refill writes (taken in the refill clock, CacheControl
    // replays its lookup): its index in fill_way is look_line's.
    Mux2 #(1) u_mux2_fill_conflict(.in0(same_index[0]), .in1(same_index[1]), .sel(fill_way),
                                   .out(fill_conflict));

    Or2  #(1) u_or2_hit(.in1(hits[0]), .in2(hits[1]), .out(hit));
    Mux2 #(DATA_WIDTH) u_mux2_hit_line(.in0(line[0]), .in1(line[1]), .sel(hits[1]),
                                       .out(hit_line));

    // Forwarding needs stores; a read-only cache has none of it.
    if (READ_ONLY) begin: g_read_only
        assign line = ram_line;
    end else begin: g_store
        wire [DATA_WIDTH-1:0] fwd_line;

        DffEn #(DATA_WIDTH) u_dff_en_fwd_line(.clk, .en(store_write), .in(merged), .out(fwd_line));

        for (genvar w = 0; w < 2; w++) begin: g_line
            wire fwd_new;      // the request taken at a store's write here
            wire fwd;          // this way's RAM read a line older than a store

            // Forwarding (see the behave version): decided at the edge of a read, per way.
            // @kb: rtl/lib/block/cache/skewed_cache/design
            And3  #(1) u_and3_fwd(.in1(store_write), .in2(hits[w]), .in3(same_index[w]),
                                  .out(fwd_new));
            DffSyncRstEn #(.WIDTH(1)) u_dff_sync_rst_en_fwd(.clk, .rst_n, .en(ram_rd), .in(fwd_new),
                                                            .out(fwd));
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

    // The victim is taken when memory takes the read of the load miss.
    DffEn #(1) u_dff_en_fill(.clk, .en(miss_taken), .in(victim_way), .out(fill_way));

endmodule

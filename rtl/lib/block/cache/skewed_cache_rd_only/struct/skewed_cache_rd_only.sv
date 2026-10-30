/* Two-way skewed-associative read-only cache (an instruction cache), made of blocks and gates.
 *
 * Same ports and behavior as the behave version (see there, and DirectCacheRdOnly for the
 * protocol). Per way the struct CacheValidRam, CacheTagRam and CacheDataRam at the way's
 * index (way 1: an Xor2 of the set and the low bits of the tag, for the request and for the
 * line looked up), a CmpEq of the tag and And3 for its hit. Control as in the struct
 * SetAssocCache without stores, plus:
 *   hit_way    = hits[1]                   hit_data = Mux2(way 0, way 1, hits[1])
 *   victim_way = ~valid[1] | (valid[0] & recent[0] & ~recent[1])
 *   recent     = per way a RegFile of one bit per line (read combinationally at the line
 *                looked up; written on touch: !touch_way in way 0, touch_way in way 1)
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
    localparam TAG_WIDTH   = ADDR_WIDTH - SETS_WIDTH - SETS_OFFSET
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

    localparam LINE_WIDTH = ADDR_WIDTH - SETS_OFFSET;   // address bits above the offset

    wire                  accept;       // a request is taken in this clock
    wire                  look;         // the request of the clock before is looked up now
    wire [LINE_WIDTH-1:0] look_line;    // its address without the offset in the line
    wire [LINE_WIDTH-1:0] look_line_next;
    wire [LINE_WIDTH-1:0] req_line;     // the request's address without the offset
    wire [1:0][SETS_WIDTH-1:0] req_index;   // the request's index in each way
    wire [1:0][SETS_WIDTH-1:0] look_index;  // look_line's index in each way
    wire [1:0]            valid;        // of the candidates of look_line
    wire [1:0]            hits;         // one-hot: the way that hits, 0 on a miss
    wire [1:0][DATA_WIDTH-1:0] data;
    wire [1:0]            wr_en;        // refill writes the way
    wire [1:0]            recent;       // the recent bits of the candidates of look_line
    wire [1:0]            recent_new;   // their new values on a touch
    wire                  hit;
    wire                  hit_n;
    wire                  miss;
    wire                  held;         // memory does not take the miss's read: it stays
    wire                  mem_ready_n;
    wire                  look_next;
    wire                  wait_start;   // memory takes the read of the miss
    wire [DATA_WIDTH-1:0] hit_data;
    wire                  valid1_n;
    wire                  recent1_n;
    wire                  pick_older;   // both valid, way 0 recent and way 1 not: way 1
    wire                  victim_way;   // the way a miss found now replaces
    wire                  fill_way;     // the way the line of the served miss goes into
    wire                  fill_way_n;
    wire                  fill_way_next;
    wire                  touch;
    wire                  touch_way;
    wire                  touch_way_n;
    wire                  waiting;      // a miss is served: the memory has not answered yet
    wire                  waiting_next;
    wire                  waiting_kept; // waiting, and the memory does not answer now
    wire                  mem_rsp_n;
    wire                  refill;       // the line from memory comes: write it

    Nor2 #(1) u_nor2_ready (.in1(waiting), .in2(miss), .out(req_ready));
    And2 #(1) u_and2_accept(.in1(req_valid), .in2(req_ready), .out(accept));

    Or2  #(1) u_or2_look   (.in1(accept), .in2(held), .out(look_next));
    DffSyncRst #(.WIDTH(1)) u_dff_sync_rst_look(.clk, .rst_n, .in(look_next), .out(look));
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
    And2 #(1) u_and2_wr_0 (.in1(refill), .in2(fill_way_n), .out(wr_en[0]));
    And2 #(1) u_and2_wr_1 (.in1(refill), .in2(fill_way), .out(wr_en[1]));

    // A hit or a fill makes its line recent and the other candidate not: the new bit of each
    // way (a vector, not (w == 0) ? ... in the port: Icarus makes that X).
    Inv  #(1) u_inv_touch (.in(touch_way), .out(touch_way_n));
    assign recent_new = {touch_way, touch_way_n};

    for (genvar w = 0; w < 2; w++) begin: g_way
        wire [TAG_WIDTH-1:0]  tag;
        wire                  tag_eq;

        CacheValidRam #(.SETS_WIDTH(SETS_WIDTH)) u_cache_valid_ram(
            .clk, .rst_n, .invalidate,
            .rd_en(accept), .rd_set(req_index[w]), .valid(valid[w]),
            .wr_en(wr_en[w]), .wr_set(look_index[w]), .wr_val(1'b1));

        CacheTagRam #(.SETS_WIDTH(SETS_WIDTH), .TAG_WIDTH(TAG_WIDTH)) u_cache_tag_ram(
            .clk,
            .rd_en(accept), .rd_set(req_index[w]), .tag,
            .wr_en(wr_en[w]), .wr_set(look_index[w]),
            .wr_tag(look_line[LINE_WIDTH-1:SETS_WIDTH]));

        CacheDataRam #(.SETS_WIDTH(SETS_WIDTH), .SETS_OFFSET(SETS_OFFSET)) u_cache_data_ram(
            .clk,
            .rd_en(accept), .rd_set(req_index[w]), .data(data[w]),
            .wr_en(wr_en[w]), .wr_set(look_index[w]), .wr_data(mem_rsp_data));

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

    Or2  #(1) u_or2_hit   (.in1(hits[0]), .in2(hits[1]), .out(hit));
    Inv  #(1) u_inv_hit   (.in(hit), .out(hit_n));
    And2 #(1) u_and2_miss (.in1(look), .in2(hit_n), .out(miss));
    Mux2 #(DATA_WIDTH) u_mux2_hit_data(.in0(data[0]), .in1(data[1]), .sel(hits[1]),
                                       .out(hit_data));

    // The victim: an invalid candidate (way 1 first), else the one not recently used, else
    // way 0: ~valid[1] | (valid[0] & recent[0] & ~recent[1]).
    Inv  #(1) u_inv_valid1 (.in(valid[1]), .out(valid1_n));
    Inv  #(1) u_inv_recent1(.in(recent[1]), .out(recent1_n));
    And3 #(1) u_and3_older (.in1(valid[0]), .in2(recent[0]), .in3(recent1_n), .out(pick_older));
    Or2  #(1) u_or2_victim (.in1(valid1_n), .in2(pick_older), .out(victim_way));

    Or2  #(1) u_or2_touch     (.in1(hit), .in2(refill), .out(touch));
    Mux2 #(1) u_mux2_touch_way(.in0(hits[1]), .in1(fill_way), .sel(refill), .out(touch_way));

    // The victim is taken when memory takes the read.
    Mux2 #(1) u_mux2_fill(.in0(fill_way), .in1(victim_way), .sel(wait_start),
                          .out(fill_way_next));
    Dff  #(1) u_dff_fill (.clk, .in(fill_way_next), .out(fill_way));

    Inv  #(1) u_inv_rsp   (.in(mem_rsp_valid), .out(mem_rsp_n));
    And2 #(1) u_and2_kept (.in1(waiting), .in2(mem_rsp_n), .out(waiting_kept));
    Inv  #(1) u_inv_mem_ready  (.in(mem_req_ready), .out(mem_ready_n));
    And2 #(1) u_and2_held      (.in1(miss), .in2(mem_ready_n), .out(held));
    And2 #(1) u_and2_wait_start(.in1(miss), .in2(mem_req_ready), .out(wait_start));
    Or2  #(1) u_or2_wait  (.in1(wait_start), .in2(waiting_kept), .out(waiting_next));
    DffSyncRst #(.WIDTH(1)) u_dff_sync_rst_wait(.clk, .rst_n, .in(waiting_next), .out(waiting));

    And2 #(1)          u_and2_refill(.in1(waiting), .in2(mem_rsp_valid), .out(refill));
    Or2  #(1)          u_or2_rsp    (.in1(hit), .in2(refill), .out(rsp_valid));
    Mux2 #(DATA_WIDTH) u_mux2_data  (.in0(hit_data), .in1(mem_rsp_data), .sel(waiting),
                                     .out(rsp_data));

    // See the behave version.
    `DC_ASSERT(a_no_look_while_waiting, !(look && waiting))

    assign mem_req_valid = miss;
    assign mem_req_addr  = {look_line, {SETS_OFFSET{1'b0}}};

endmodule

/* Direct-mapped read-only cache (an instruction cache), made of blocks and gates.
 *
 * Same ports and behavior as the behave version (see there for the protocol): a request is
 * taken while req_ready=1; a hit answers 1 clock later; a miss asks memory for its line,
 * answers with the line from memory and writes it; invalidate makes every line invalid.
 *
 * The RAMs are the struct CacheValidRam, CacheTagRam and CacheDataRam. Control:
 *   req_ready = NOR(waiting, miss)            accept = req_valid AND req_ready
 *   look      = DffSyncRst(accept OR held)    look_line: Dff with a hold Mux2 (accept)
 *   hit       = look AND valid AND (tag == tag of look_line)   miss = look AND NOT hit
 *   held      = miss AND NOT mem_req_ready    mem_req_valid = miss
 *   waiting   = DffSyncRst((miss AND mem_req_ready) OR (waiting AND NOT mem_rsp_valid))
 *   refill    = waiting AND mem_rsp_valid     rsp_valid = hit OR refill
 *   rsp_data  = Mux2(data, mem_rsp_data, waiting)
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "dark_circuit_assert.svh"

module DirectCacheRdOnly #(
    parameter  ADDR_WIDTH  = 32,            // byte address
    parameter  SETS_WIDTH  = 6,             // 1 << SETS_WIDTH sets
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
    localparam LINE_WIDTH = ADDR_WIDTH - SETS_OFFSET;   // address bits above the offset

    wire                  accept;       // a request is taken in this clock
    wire                  look;         // the request of the clock before is looked up now
    wire [LINE_WIDTH-1:0] look_line;    // its address without the offset in the line
    wire [LINE_WIDTH-1:0] look_line_next;
    wire                  hit;
    wire                  miss;
    wire                  held;         // memory does not take the miss's read: it stays
    wire                  mem_ready_n;
    wire                  look_next;
    wire                  wait_start;   // memory takes the read of the miss
    wire                  hit_n;
    wire                  tag_eq;
    wire                  waiting;      // a miss is served: the memory has not answered yet
    wire                  waiting_next;
    wire                  waiting_kept; // waiting, and the memory does not answer now
    wire                  mem_rsp_n;
    wire                  valid;        // of the set of look_line, read in the clock before
    wire [TAG_WIDTH-1:0]  tag;
    wire [DATA_WIDTH-1:0] data;
    wire                  refill;       // the line from memory comes: write it

    Nor2 #(1) u_nor2_ready (.in1(waiting), .in2(miss), .out(req_ready));
    And2 #(1) u_and2_accept(.in1(req_valid), .in2(req_ready), .out(accept));

    Or2  #(1) u_or2_look   (.in1(accept), .in2(held), .out(look_next));
    DffSyncRst #(.WIDTH(1)) u_dff_sync_rst_look(.clk(clk), .rst_n(rst_n), .in(look_next),
                                                .out(look));
    Mux2 #(LINE_WIDTH) u_mux2_line(.in0(look_line), .in1(req_addr[ADDR_WIDTH-1:SETS_OFFSET]),
                                   .sel(accept), .out(look_line_next));
    Dff  #(LINE_WIDTH) u_dff_line (.clk(clk), .in(look_line_next), .out(look_line));

    CacheValidRam #(.SETS_WIDTH(SETS_WIDTH)) u_cache_valid_ram(
        .clk, .rst_n, .invalidate,
        .rd_en(accept), .rd_set(req_addr[SETS_OFFSET +: SETS_WIDTH]), .valid,
        .wr_en(refill), .wr_set(look_line[SETS_WIDTH-1:0]), .wr_val(1'b1));

    CacheTagRam #(.SETS_WIDTH(SETS_WIDTH), .TAG_WIDTH(TAG_WIDTH)) u_cache_tag_ram(
        .clk,
        .rd_en(accept), .rd_set(req_addr[SETS_OFFSET +: SETS_WIDTH]), .tag,
        .wr_en(refill), .wr_set(look_line[SETS_WIDTH-1:0]),
        .wr_tag(look_line[LINE_WIDTH-1:SETS_WIDTH]));

    CacheDataRam #(.SETS_WIDTH(SETS_WIDTH), .SETS_OFFSET(SETS_OFFSET)) u_cache_data_ram(
        .clk,
        .rd_en(accept), .rd_set(req_addr[SETS_OFFSET +: SETS_WIDTH]), .data,
        .wr_en(refill), .wr_set(look_line[SETS_WIDTH-1:0]), .wr_data(mem_rsp_data));

    CmpEq #(TAG_WIDTH) u_cmp_eq(.in1(tag), .in2(look_line[LINE_WIDTH-1:SETS_WIDTH]), .eq(tag_eq));
    And3  #(1) u_and3_hit (.in1(look), .in2(valid), .in3(tag_eq), .out(hit));
    Inv   #(1) u_inv_hit  (.in(hit), .out(hit_n));
    And2  #(1) u_and2_miss(.in1(look), .in2(hit_n), .out(miss));

    Inv  #(1) u_inv_rsp   (.in(mem_rsp_valid), .out(mem_rsp_n));
    And2 #(1) u_and2_kept (.in1(waiting), .in2(mem_rsp_n), .out(waiting_kept));
    Inv  #(1) u_inv_mem_ready  (.in(mem_req_ready), .out(mem_ready_n));
    And2 #(1) u_and2_held      (.in1(miss), .in2(mem_ready_n), .out(held));
    And2 #(1) u_and2_wait_start(.in1(miss), .in2(mem_req_ready), .out(wait_start));
    Or2  #(1) u_or2_wait  (.in1(wait_start), .in2(waiting_kept), .out(waiting_next));
    DffSyncRst #(.WIDTH(1)) u_dff_sync_rst_wait(.clk(clk), .rst_n(rst_n), .in(waiting_next),
                                                .out(waiting));

    And2 #(1)          u_and2_refill(.in1(waiting), .in2(mem_rsp_valid), .out(refill));
    Or2  #(1)          u_or2_rsp    (.in1(hit), .in2(refill), .out(rsp_valid));
    Mux2 #(DATA_WIDTH) u_mux2_data  (.in0(data), .in1(mem_rsp_data), .sel(waiting),
                                     .out(rsp_data));

    // See the behave version.
    `DC_ASSERT(a_no_look_while_waiting, !(look && waiting))

    assign mem_req_valid = miss;
    assign mem_req_addr  = {look_line, {SETS_OFFSET{1'b0}}};

endmodule

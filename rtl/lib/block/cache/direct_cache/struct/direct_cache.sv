/* Direct-mapped read-write cache (a data cache), write-through, made of blocks and gates.
 *
 * Same ports, parameters and behavior as the behave version (see there for the protocol, the
 * write policy, forwarding and READ_ONLY). The RAMs are the struct CacheValidRam,
 * CacheTagRam and CacheDataRam; the request taken is a DffEn (accept) for the line address
 * and, unless READ_ONLY, one for the fields of a store (we, wdata, wstrb).
 * Control (READ_ONLY=1: we, wdata, wstrb, store_write and fwd are 0, the data RAM writes
 * mem_rsp_data, and their logic is left out):
 *   req_ready = NOR(waiting, load_miss, held)       accept = req_valid AND req_ready
 *   look      = DffSyncRst(accept OR held)
 *   hit       = look AND valid AND (tag == tag of look_line)
 *   store     = look AND we      load_hit/load_miss = look AND NOT we AND hit / NOT hit
 *   mem_req_valid = store OR load_miss              held = mem_req_valid AND NOT mem_req_ready
 *   merged    = per byte Mux2(byte of line, byte of wdata, its strobe)
 *   store_write = store AND hit AND mem_req_ready
 *   waiting   = DffSyncRst((load_miss AND mem_req_ready) OR (waiting AND NOT mem_rsp_valid))
 *   refill    = waiting AND mem_rsp_valid
 *   data RAM write: refill OR store_write, Mux2(merged, mem_rsp_data, refill)
 *   fwd       = DffSyncRstEn(en accept) of store_write AND (set == set of the request)
 *   fwd_line  = DffEn (store_write) of merged
 *   line      = Mux2(ram_line, fwd_line, fwd)       rsp_data = Mux2(line, mem_rsp_data, waiting)
 *   rsp_valid = load_hit OR refill
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "dark_circuit_assert.svh"

module DirectCache #(
    parameter  ADDR_WIDTH  = 32,            // byte address
    parameter  SETS_WIDTH  = 6,             // 1 << SETS_WIDTH sets
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
    localparam LINE_WIDTH = ADDR_WIDTH - SETS_OFFSET;   // address bits above the offset
    localparam STORE_WIDTH = 1 + DATA_WIDTH + STRB_WIDTH;   // the fields of a store kept

    wire                  accept;       // a request is taken in this clock
    wire                  look;         // a request taken before is looked up now (or held)
    wire                  look_next;
    wire [LINE_WIDTH-1:0] look_line;    // its address without the offset in the line
    wire                  look_we;
    wire                  look_we_n;
    wire [DATA_WIDTH-1:0] look_wdata;
    wire [STRB_WIDTH-1:0] look_wstrb;
    wire                  valid;        // of the set of look_line, read with the request
    wire [TAG_WIDTH-1:0]  tag;
    wire                  tag_eq;
    wire [DATA_WIDTH-1:0] ram_line;     // line of the set as the RAM read it
    wire [DATA_WIDTH-1:0] line;         // line of the set now: forwarded or ram_line
    wire                  hit;
    wire                  hit_n;
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
    wire                  ram_wr_en;
    wire [DATA_WIDTH-1:0] ram_wr_line;

    Nor3 #(1) u_nor3_ready (.in1(waiting), .in2(load_miss), .in3(held), .out(req_ready));
    And2 #(1) u_and2_accept(.in1(req_valid), .in2(req_ready), .out(accept));

    Or2 #(1) u_or2_look(.in1(accept), .in2(held), .out(look_next));
    DffSyncRst #(.WIDTH(1)) u_dff_sync_rst_look(.clk, .rst_n, .in(look_next), .out(look));

    // The line address of the request taken, kept for its lookup.
    DffEn #(LINE_WIDTH) u_dff_en_line(.clk, .en(accept), .in(req_addr[ADDR_WIDTH-1:SETS_OFFSET]),
                                      .out(look_line));

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
        .rd_en(accept), .rd_set(req_addr[SETS_OFFSET +: SETS_WIDTH]), .data(ram_line),
        .wr_en(ram_wr_en), .wr_set(look_line[SETS_WIDTH-1:0]), .wr_data(ram_wr_line));

    // Lookup.
    CmpEq #(TAG_WIDTH) u_cmp_eq_tag(.in1(tag), .in2(look_line[LINE_WIDTH-1:SETS_WIDTH]),
                                    .eq(tag_eq));
    And3 #(1) u_and3_hit      (.in1(look), .in2(valid), .in3(tag_eq), .out(hit));
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
        wire [DATA_WIDTH-1:0]  merged;          // line with the bytes of the store
        wire                   same_set;        // the request taken is of the lookup's set
        wire                   fwd_new;         // the request taken at a store's write, same set
        wire                   fwd;             // ram_line is older than a store's write
        wire [DATA_WIDTH-1:0]  fwd_line;

        // The fields of the store taken, kept for its lookup.
        DffEn #(STORE_WIDTH) u_dff_en_store(.clk, .en(accept), .in({req_we, req_wdata, req_wstrb}),
                                            .out(look_store));
        assign {look_we, look_wdata, look_wstrb} = look_store;

        // Store: the bytes of its strobes into the line, written when memory takes the store.
        for (genvar b = 0; b < STRB_WIDTH; b++) begin: g_byte
            Mux2 #(8) u_mux2_byte(.in0(line[8*b +: 8]), .in1(look_wdata[8*b +: 8]),
                                  .sel(look_wstrb[b]), .out(merged[8*b +: 8]));
        end
        And3 #(1) u_and3_store_write(.in1(store), .in2(hit), .in3(mem_req_ready),
                                     .out(store_write));
        Mux2 #(DATA_WIDTH) u_mux2_ram_wr(.in0(merged), .in1(mem_rsp_data), .sel(refill),
                                         .out(ram_wr_line));

        // Forwarding (see the behave version): decided at the edge of a read.
        CmpEq #(SETS_WIDTH) u_cmp_eq_set(.in1(look_line[SETS_WIDTH-1:0]),
                                         .in2(req_addr[SETS_OFFSET +: SETS_WIDTH]),
                                         .eq(same_set));
        And2  #(1) u_and2_fwd (.in1(store_write), .in2(same_set), .out(fwd_new));
        DffSyncRstEn #(.WIDTH(1)) u_dff_sync_rst_en_fwd(.clk, .rst_n, .en(accept), .in(fwd_new),
                                                        .out(fwd));
        DffEn #(DATA_WIDTH) u_dff_en_fwd_line(.clk, .en(store_write), .in(merged), .out(fwd_line));
        Mux2 #(DATA_WIDTH) u_mux2_line_fwd(.in0(ram_line), .in1(fwd_line), .sel(fwd),
                                           .out(line));
    end

    // Load miss served from the clock memory takes its read until the answer comes.
    And2 #(1) u_and2_wait_start(.in1(load_miss), .in2(mem_req_ready), .out(wait_start));
    Inv  #(1) u_inv_rsp        (.in(mem_rsp_valid), .out(mem_rsp_n));
    And2 #(1) u_and2_kept      (.in1(waiting), .in2(mem_rsp_n), .out(waiting_kept));
    Or2  #(1) u_or2_wait       (.in1(wait_start), .in2(waiting_kept), .out(waiting_next));
    DffSyncRst #(.WIDTH(1)) u_dff_sync_rst_wait(.clk, .rst_n, .in(waiting_next), .out(waiting));
    And2 #(1) u_and2_refill    (.in1(waiting), .in2(mem_rsp_valid), .out(refill));

    // See the behave version.
    `DC_ASSERT(a_no_look_while_waiting, !(look && waiting))

    Or2 #(1) u_or2_ram_wr(.in1(refill), .in2(store_write), .out(ram_wr_en));

    Or2  #(1)          u_or2_rsp  (.in1(load_hit), .in2(refill), .out(rsp_valid));
    Mux2 #(DATA_WIDTH) u_mux2_data(.in0(line), .in1(mem_rsp_data), .sel(waiting),
                                   .out(rsp_data));

endmodule

/* Control of a read-write cache (write-through), made of blocks and gates: the part
 * DirectCache, SetAssocCache and SkewedCache share.
 *
 * Same ports, parameters and behavior as the behave version (see there). The request taken is
 * a DffEn (accept) for the line address and, unless READ_ONLY, one for the fields of a store
 * (we, wdata, wstrb).
 *   look        = DffSyncRst(accept OR held)
 *   store       = look AND look_we             load = look AND ~look_we
 *   load_hit    = load AND hit                 load_miss = load AND ~hit
 *   look_req    = store OR load_miss           held = look_req AND ~mem_req_ready
 *   miss_taken  = load_miss AND mem_req_ready  waiting = DffSyncRst(miss_taken OR
 *                                                         (waiting AND ~mem_rsp_valid))
 *   refill      = waiting AND mem_rsp_valid
 *   store_write = store AND hit AND mem_req_ready (g_store); merged: per byte a Mux2 of the hit
 *                 line and the store's byte on its strobe; ram_wr_line = Mux2(merged,
 *                 mem_rsp_data, refill)
 *   rsp_valid   = load_hit OR refill OR (unc_waiting AND mem_rsp_valid)
 *   rsp_data    = Mux2(hit_line, mem_rsp_data, waiting OR unc_waiting)
 * Uncached (see the behave version):
 *   idle      = Nor3(look, waiting, unc_busy)      unc_busy = unc_waiting AND ~mem_rsp_valid
 *   req_ready = Mux2(NorReduce(waiting, load_miss, held, unc_busy), idle AND mem_req_ready,
 *                    req_uncached)
 *   unc_pass  = req_valid AND req_uncached AND idle; the memory line a Mux2 of look_line and
 *               the request's on unc_pass, the fields of a write (g_store) one of the store kept
 *               and the request's; unc_waiting a DffSyncRst like waiting
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "dark_circuit_assert.svh"

module CacheControl #(
    parameter  ADDR_WIDTH  = 32,            // byte address
    parameter  SETS_OFFSET = 2,             // 1 << SETS_OFFSET bytes in a line (2: one word)
    parameter  READ_ONLY   = 0,             // 1: loads only, no store logic
    localparam DATA_WIDTH  = 8 << SETS_OFFSET,
    localparam STRB_WIDTH  = 1 << SETS_OFFSET   // a strobe per byte of the line
)(
    input  wire                  clk,
    input  wire                  rst_n,         // synchronous reset, active low

    // CPU side: requests (a channel), answers to loads
    input  wire                  req_valid,
    output wire                  req_ready,     // uncached: follows mem_req_ready, no flop
    input  wire                  req_uncached,  // the request bypasses the lines
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
    input  wire [DATA_WIDTH-1:0] mem_rsp_data,

    // The cache's ways: the lookup, and what it found
    output wire                  accept,        // a request is taken: the RAMs read it
    output wire                  look,          // a request taken before is looked up (or held)
    output wire [ADDR_WIDTH-1:SETS_OFFSET] look_line,   // its line: address without the offset
    output wire                  load_hit,      // a load hits now: replacement touch
    output wire                  store_write,   // a store that hits is taken: write merged
    output wire                  refill,        // the missed line comes: write it
    output wire                  miss_taken,    // memory takes a load miss's read: the victim
    output wire [DATA_WIDTH-1:0] ram_wr_line,   // what a data RAM write writes: refill or merged
    output wire [DATA_WIDTH-1:0] merged,        // the hit line with the store's bytes
    input  wire                  hit,           // a way hits the lookup
    input  wire [DATA_WIDTH-1:0] hit_line       // the line of the way that hits
);
    localparam LINE_WIDTH  = ADDR_WIDTH - SETS_OFFSET;      // address bits above the offset
    localparam STORE_WIDTH = 1 + DATA_WIDTH + STRB_WIDTH;   // the fields of a store kept

    wire                  look_next;
    wire [LINE_WIDTH-1:0] req_line;     // the request's address without the offset
    wire                  look_we;
    wire                  look_we_n;
    wire                  hit_n;
    wire                  store;        // a store is looked up
    wire                  load;         // a load is looked up
    wire                  load_miss;
    wire                  mem_ready_n;
    wire                  look_req;     // the lookup asks memory: a store or a load miss
    wire [LINE_WIDTH-1:0] mem_line;     // the line memory is asked for
    wire                  held;         // its memory request is not taken: the lookup stays
    wire                  waiting;      // a load miss is served: memory has not answered yet
    wire                  waiting_next;
    wire                  waiting_kept; // waiting, and memory does not answer now
    wire                  mem_rsp_n;
    wire                  uncached_n;
    wire                  ready_cached; // a cached request may be taken
    wire                  ready_unc;    // an uncached one may be taken
    wire                  idle;         // nothing looked up or served: uncached may pass
    wire                  unc_pass;     // an uncached request goes to memory now
    wire                  unc_waiting;  // memory took an uncached read, has not answered yet
    wire                  unc_busy;     // ... and does not answer now
    wire                  unc_start;    // memory takes an uncached read
    wire                  unc_next;
    wire                  unc_rsp;      // memory answers the uncached read
    wire                  mem_we_n;
    wire                  rsp_mem;      // the answer is memory's line

    // A cached request is taken when the lookup is done and no uncached read waits; an
    // uncached one passes to memory while idle and is taken when memory takes it.
    // @kb: rtl/lib/block/cache/uncached
    And2 #(1) u_and2_unc_busy (.in1(unc_waiting), .in2(mem_rsp_n), .out(unc_busy));
    Nor3 #(1) u_nor3_idle     (.in1(look), .in2(waiting), .in3(unc_busy), .out(idle));
    NorReduce #(4) u_nor_reduce_ready_cached(.in({waiting, load_miss, held, unc_busy}),
                                             .out(ready_cached));
    And2 #(1) u_and2_ready_unc(.in1(idle), .in2(mem_req_ready), .out(ready_unc));
    Mux2 #(1) u_mux2_ready    (.in0(ready_cached), .in1(ready_unc), .sel(req_uncached),
                               .out(req_ready));
    Inv  #(1) u_inv_uncached  (.in(req_uncached), .out(uncached_n));
    And3 #(1) u_and3_accept   (.in1(req_valid), .in2(uncached_n), .in3(req_ready),
                               .out(accept));
    And3 #(1) u_and3_unc_pass (.in1(req_valid), .in2(req_uncached), .in3(idle),
                               .out(unc_pass));

    Or2 #(1) u_or2_look(.in1(accept), .in2(held), .out(look_next));
    DffSyncRst #(.WIDTH(1)) u_dff_sync_rst_look(.clk, .rst_n, .in(look_next), .out(look));

    // The line address of the request taken, kept for its lookup.
    assign req_line = req_addr[ADDR_WIDTH-1:SETS_OFFSET];
    DffEn #(LINE_WIDTH) u_dff_en_line(.clk, .en(accept), .in(req_line), .out(look_line));

    // Lookup.
    Inv  #(1) u_inv_hit       (.in(hit), .out(hit_n));
    Inv  #(1) u_inv_we        (.in(look_we), .out(look_we_n));
    And2 #(1) u_and2_store    (.in1(look), .in2(look_we), .out(store));
    And2 #(1) u_and2_load     (.in1(look), .in2(look_we_n), .out(load));
    And2 #(1) u_and2_load_hit (.in1(load), .in2(hit), .out(load_hit));
    And2 #(1) u_and2_load_miss(.in1(load), .in2(hit_n), .out(load_miss));

    // Memory request: a store always, a load when it misses (from the lookup's registers), an
    // uncached request as it comes (only while idle); the fields of a write in the branches.
    Or2  #(1) u_or2_look_req (.in1(store), .in2(load_miss), .out(look_req));
    Or2  #(1) u_or2_mem_valid(.in1(unc_pass), .in2(look_req), .out(mem_req_valid));
    Inv  #(1) u_inv_mem_ready(.in(mem_req_ready), .out(mem_ready_n));
    And2 #(1) u_and2_held    (.in1(look_req), .in2(mem_ready_n), .out(held));
    Mux2 #(LINE_WIDTH) u_mux2_mem_line(.in0(look_line), .in1(req_line), .sel(unc_pass),
                                       .out(mem_line));
    assign mem_req_addr = {mem_line, {SETS_OFFSET{1'b0}}};

    // The logic only stores need; a read-only cache has none of it. Both branches drive
    // look_we, store_write, merged, ram_wr_line and the fields of a memory write (mem_req_we,
    // mem_req_wdata, mem_req_wstrb).
    // @kb: rtl/lib/block/cache/read_only
    if (READ_ONLY) begin: g_read_only
        assign look_we     = 1'b0;
        assign store_write = 1'b0;
        assign merged      = '0;
        assign ram_wr_line = mem_rsp_data;

        assign mem_req_we    = 1'b0;
        assign mem_req_wdata = '0;
        assign mem_req_wstrb = '0;
    end else begin: g_store
        wire [STORE_WIDTH-1:0] look_store;      // {we, wdata, wstrb} of the lookup
        wire [DATA_WIDTH-1:0]  look_wdata;
        wire [STRB_WIDTH-1:0]  look_wstrb;

        // The fields of the store taken, kept for its lookup.
        DffEn #(STORE_WIDTH) u_dff_en_store(.clk, .en(accept), .in({req_we, req_wdata, req_wstrb}),
                                            .out(look_store));
        assign {look_we, look_wdata, look_wstrb} = look_store;

        // A memory write: an uncached store as it comes, else the lookup's store.
        Mux2 #(STORE_WIDTH) u_mux2_mem_store(
            .in0(look_store), .in1({req_we, req_wdata, req_wstrb}), .sel(unc_pass),
            .out({mem_req_we, mem_req_wdata, mem_req_wstrb}));

        // Store: the bytes of its strobes into the line, written when memory takes the store.
        for (genvar b = 0; b < STRB_WIDTH; b++) begin: g_byte
            Mux2 #(8) u_mux2_byte(.in0(hit_line[8*b +: 8]), .in1(look_wdata[8*b +: 8]),
                                  .sel(look_wstrb[b]), .out(merged[8*b +: 8]));
        end
        And3 #(1) u_and3_store_write(.in1(store), .in2(hit), .in3(mem_req_ready),
                                     .out(store_write));
        Mux2 #(DATA_WIDTH) u_mux2_ram_wr(.in0(merged), .in1(mem_rsp_data), .sel(refill),
                                         .out(ram_wr_line));
    end

    // Load miss served from the clock memory takes its read until the answer comes.
    And2 #(1) u_and2_miss_taken(.in1(load_miss), .in2(mem_req_ready), .out(miss_taken));
    Inv  #(1) u_inv_rsp        (.in(mem_rsp_valid), .out(mem_rsp_n));
    And2 #(1) u_and2_kept      (.in1(waiting), .in2(mem_rsp_n), .out(waiting_kept));
    Or2  #(1) u_or2_wait       (.in1(miss_taken), .in2(waiting_kept), .out(waiting_next));
    DffSyncRst #(.WIDTH(1)) u_dff_sync_rst_wait(.clk, .rst_n, .in(waiting_next), .out(waiting));
    And2 #(1) u_and2_refill    (.in1(waiting), .in2(mem_rsp_valid), .out(refill));

    // See the behave version.
    `DC_ASSERT(a_no_look_while_waiting, !(look && waiting))

    // Uncached read served from the clock memory takes it until the answer comes.
    Inv  #(1) u_inv_mem_we    (.in(mem_req_we), .out(mem_we_n));
    And3 #(1) u_and3_unc_start(.in1(unc_pass), .in2(mem_req_ready), .in3(mem_we_n),
                               .out(unc_start));
    Or2  #(1) u_or2_unc_wait  (.in1(unc_start), .in2(unc_busy), .out(unc_next));
    DffSyncRst #(.WIDTH(1)) u_dff_sync_rst_unc_wait(.clk, .rst_n, .in(unc_next),
                                                    .out(unc_waiting));
    And2 #(1) u_and2_unc_rsp  (.in1(unc_waiting), .in2(mem_rsp_valid), .out(unc_rsp));

    // See the behave version.
    `DC_ASSERT(a_unc_alone, !(unc_waiting && (look || waiting)))

    Or3  #(1)          u_or3_rsp    (.in1(load_hit), .in2(refill), .in3(unc_rsp), .out(rsp_valid));
    Or2  #(1)          u_or2_rsp_mem(.in1(waiting), .in2(unc_waiting), .out(rsp_mem));
    Mux2 #(DATA_WIDTH) u_mux2_data  (.in0(hit_line), .in1(mem_rsp_data), .sel(rsp_mem),
                                     .out(rsp_data));

endmodule

/* Control of a read-write cache (write-through), made of blocks and gates: the part
 * DirectCache, SetAssocCache and SkewedCache share.
 *
 * Same ports, parameters and behavior as the behave version (see there). The request taken is
 * a DffEn (accept) for the line address and, unless READ_ONLY, one for the fields of a store
 * (we, wdata, wstrb).
 *   look        = DffSyncRst(accept OR held OR replay)     look_ok = look AND ~replay
 *   store       = look_ok AND look_we          load = look_ok AND ~look_we
 *   load_hit    = load AND hit                 load_miss = load AND ~hit (atomic: below)
 *   look_req    = store OR load_miss           held = look_req AND ~mem_req_ready
 *   served      = load_miss AND mem_req_ready  waiting = DffSyncRst(served OR
 *                                                         (waiting AND ~mem_rsp_valid))
 *   answer      = waiting AND mem_rsp_valid    refill = answer AND ~wait_nocache
 *   replay      = DffSyncRst(accept AND refill AND fill_conflict)   ram_rd = accept OR replay
 *   store_write = store AND hit AND mem_req_ready (g_store); merged: per byte a Mux2 of the hit
 *                 line and the store's byte on its strobe; ram_wr_line = Mux2(merged,
 *                 mem_rsp_data, refill)
 *   rsp_valid   = load_hit OR answer OR (unc_waiting AND mem_rsp_valid)
 *   rsp_data    = Mux2(hit_line, mem_rsp_data, waiting OR unc_waiting)
 * Uncached (see the behave version):
 *   idle      = Nor3(look, waiting, unc_busy)      unc_busy = unc_waiting AND ~mem_rsp_valid
 *   req_ready = Mux2(NorReduce(waiting_kept, replay, load_miss, held, unc_busy),
 *                    idle AND mem_req_ready, req_uncached_dbg_bypass)
 *   unc_pass  = req_valid AND req_uncached_dbg_bypass AND idle; the memory address a Mux2 of the
 * line's
 *               and the request's own on unc_pass, the size one of SETS_OFFSET and req_size,
 *               the fields of a write (g_store) one of the store kept
 *               and the request's; unc_waiting a DffSyncRst like waiting
 * No cache (see the behave version): look_nocache, look_size and look_offset kept with the
 *   request (DffEn); the lookup's memory address has look_offset AND look_nocache, its
 *   size a Mux2 of SETS_OFFSET and look_size; miss_taken = served AND ~look_exact;
 *   wait_nocache a DffEn of look_exact on served
 * Atomic (see the behave version): look_atop a DffEn with the store (g_store), look_atomic
 *   = OrReduce(look_atop[5:4]), look_exact = look_nocache OR look_atomic (in place of
 *   look_nocache above); load_hit = load AND hit AND ~look_atomic, load_miss = load AND
 *   (~hit OR look_atomic); drop = served AND look_atomic AND hit; mem_req_atop a Mux2 of
 *   look_atop and req_atop on unc_pass
 * CBO (see the behave version): look_cmo a DffEn with the store, look_drops = look_cmo[1],
 *   look_cbo = OrReduce(look_cmo); cbo_drop = store AND look_drops (one more input of the
 *   NorReduce of req_ready); store_write AND ~look_cbo; drop = the atomic's OR (cbo_drop AND
 *   hit AND mem_req_ready); mem_req_cmo with mem_req_atop in the Mux2
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "dark_circuit_assert.svh"

module CacheControl import AtomicPkg::*, CachePkg::*; #(
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
    input  wire                  req_uncached_dbg_bypass,   // debug/test mode: straight to
                                                            // memory, no lookup
    input  wire [2:0]            req_size,      // 1 << req_size bytes (AXI AxSIZE): bypass,
                                                // no cache
    input  wire                  req_nocache,   // the address may not be cached (a
                                                // device's): looked up, never filled
    // The fields of a store, an atomic and a CBO are not used when READ_ONLY=1.
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire                  req_we,        // 1: store, 0: load
    input  wire [ADDR_WIDTH-1:0] req_addr,
    input  wire [DATA_WIDTH-1:0] req_wdata,     // store: the line with its new bytes
    input  wire [STRB_WIDTH-1:0] req_wstrb,     // store: the bytes to write
    input  atop_t                req_atop,      // ATOP_NONE, or an atomic operation (a load)
    input  cmo_t                 req_cmo,       // CMO_NONE, or a CBO (a store, no strobes)
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
    output atop_t                mem_req_atop,  // an atomic's operation, else ATOP_NONE
    output cmo_t                 mem_req_cmo,   // a CBO's operation, else CMO_NONE
    input  wire                  mem_rsp_valid,
    input  wire [DATA_WIDTH-1:0] mem_rsp_data,

    // The cache's ways: the lookup, and what it found
    output wire                  ram_rd,        // the RAMs read: a request taken, or a replay
    output wire                  replay,        // the lookup reads its RAMs again: no hit, no miss
    output wire                  look,          // a request taken before is looked up (or held)
    output wire [ADDR_WIDTH-1:SETS_OFFSET] look_line,   // its line: address without the offset
    output wire                  load_hit,      // a load hits now: replacement touch
    output wire                  store_write,   // a store that hits is taken: write merged
    output wire                  refill,        // the missed line comes: write it
    output wire                  miss_taken,    // memory takes a load miss's read: the victim
    output wire [DATA_WIDTH-1:0] ram_wr_line,   // what a data RAM write writes: refill or merged
    output wire [DATA_WIDTH-1:0] merged,        // the hit line with the store's bytes
    output wire                  drop,          // an atomic's or a CBO's line hits: clear it
    input  wire                  hit,         // a way hits the lookup
    input  wire                  fill_conflict, // the request is at the place the refill writes
    input  wire [DATA_WIDTH-1:0] hit_line       // the line of the way that hits
);
    localparam LINE_WIDTH  = ADDR_WIDTH - SETS_OFFSET;      // address bits above the offset
    localparam STORE_WIDTH = 1 + DATA_WIDTH + STRB_WIDTH + $bits(atop_t) + $bits(cmo_t);
                                                            // the fields of a store kept

    `DC_STATIC_ASSERT(a_size_fits, SETS_OFFSET <= 7)

    wire                  accept;       // a cached request is taken
    wire                  look_ok;      // the lookup is no replay: its RAM outputs are its own
    wire                  replay_n;
    wire                  replay_next;
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
    wire                  look_nocache; // the lookup's request may not be cached
    wire                  look_atomic;  // ... is atomic
    wire                  atomic_n;
    wire                  look_exact;   // ... goes to memory as asked: no cache, or atomic
    wire                  exact_n;
    wire                  miss_cond;    // a load misses: no hit, or atomic
    wire [SETS_OFFSET-1:0] look_offset; // its offset and size: memory gets them as asked
    wire [2:0]            look_size;
    wire [SETS_OFFSET-1:0] look_mem_offset; // the lookup's: its own, or 0 for a line
    wire [2:0]            look_mem_size;
    wire                  served;       // memory takes a load miss's read
    wire                  wait_nocache; // the read served may not be cached: no fill
    wire                  wait_cache;
    wire                  answer;       // the served read's answer comes
    wire                  look_drops;   // the lookup is a CBO inval or flush
    wire                  cbo_drop;     // ... looked up as a store: no request taken now
    wire                  cbo_drop_now; // ... that hits, taken by memory: drop its line
    wire                  atomic_drop;  // an atomic that hits, its read taken: drop its line

    // A cached request is taken when the lookup is done and no uncached read waits; an
    // uncached one passes to memory while idle and is taken when memory takes it.
    // @kb: rtl/lib/block/cache/uncached
    And2 #(1) u_and2_unc_busy (.in1(unc_waiting), .in2(mem_rsp_n), .out(unc_busy));
    Nor3 #(1) u_nor3_idle     (.in1(look), .in2(waiting), .in3(unc_busy), .out(idle));
    // @kb: rtl/lib/block/cache/cache_control/refill_take
    // @kb: rtl/lib/block/cache/cbo
    NorReduce #(6) u_nor_reduce_ready_cached(
        .in({waiting_kept, replay, load_miss, held, unc_busy, cbo_drop}), .out(ready_cached));
    And2 #(1) u_and2_ready_unc(.in1(idle), .in2(mem_req_ready), .out(ready_unc));
    Mux2 #(1) u_mux2_ready    (.in0(ready_cached), .in1(ready_unc), .sel(req_uncached_dbg_bypass),
                               .out(req_ready));
    Inv  #(1) u_inv_uncached  (.in(req_uncached_dbg_bypass), .out(uncached_n));
    And3 #(1) u_and3_accept   (.in1(req_valid), .in2(uncached_n), .in3(req_ready),
                               .out(accept));
    And3 #(1) u_and3_unc_pass (.in1(req_valid), .in2(req_uncached_dbg_bypass), .in3(idle),
                               .out(unc_pass));

    Or3 #(1) u_or3_look(.in1(accept), .in2(held), .in3(replay), .out(look_next));
    DffSyncRst #(.WIDTH(1)) u_dff_sync_rst_look(.clk, .rst_n, .in(look_next), .out(look));

    // The line address of the request taken, kept for its lookup.
    assign req_line = req_addr[ADDR_WIDTH-1:SETS_OFFSET];
    DffEn #(LINE_WIDTH) u_dff_en_line(.clk, .en(accept), .in(req_line), .out(look_line));
    DffEn #(SETS_OFFSET + 4) u_dff_en_nocache(
        .clk, .en(accept), .in({req_addr[SETS_OFFSET-1:0], req_size, req_nocache}),
        .out({look_offset, look_size, look_nocache}));
    Or2   #(1) u_or2_exact (.in1(look_nocache), .in2(look_atomic), .out(look_exact));
    Inv   #(1) u_inv_exact (.in(look_exact), .out(exact_n));
    Inv   #(1) u_inv_atomic(.in(look_atomic), .out(atomic_n));

    // Lookup. An atomic never hits: its line, if there, is dropped when memory takes its read.
    // @kb: rtl/lib/block/cache/atomic
    Inv  #(1) u_inv_hit       (.in(hit), .out(hit_n));
    Inv  #(1) u_inv_we        (.in(look_we), .out(look_we_n));
    Inv  #(1) u_inv_replay    (.in(replay), .out(replay_n));
    And2 #(1) u_and2_look_ok  (.in1(look), .in2(replay_n), .out(look_ok));
    And2 #(1) u_and2_store    (.in1(look_ok), .in2(look_we), .out(store));
    And2 #(1) u_and2_load     (.in1(look_ok), .in2(look_we_n), .out(load));
    And3 #(1) u_and3_load_hit (.in1(load), .in2(hit), .in3(atomic_n), .out(load_hit));
    Or2  #(1) u_or2_miss_cond (.in1(hit_n), .in2(look_atomic), .out(miss_cond));
    And2 #(1) u_and2_load_miss(.in1(load), .in2(miss_cond), .out(load_miss));

    // Memory request: a store always, a load when it misses (from the lookup's registers), an
    // uncached request as it comes (only while idle); the fields of a write in the branches.
    Or2  #(1) u_or2_look_req (.in1(store), .in2(load_miss), .out(look_req));
    Or2  #(1) u_or2_mem_valid(.in1(unc_pass), .in2(look_req), .out(mem_req_valid));
    Inv  #(1) u_inv_mem_ready(.in(mem_req_ready), .out(mem_ready_n));
    And2 #(1) u_and2_held    (.in1(look_req), .in2(mem_ready_n), .out(held));
    // An uncached request as the CPU asked it (address and size), a no-cache or atomic one as
    // its lookup kept it, a cached one a line.
    // @kb: rtl/lib/block/cache/uncached
    And2 #(SETS_OFFSET) u_and2_look_offset(.in1(look_offset), .in2({SETS_OFFSET{look_exact}}),
                                          .out(look_mem_offset));
    Mux2 #(3) u_mux2_look_size(.in0(3'(SETS_OFFSET)), .in1(look_size), .sel(look_exact),
                               .out(look_mem_size));
    Mux2 #(ADDR_WIDTH) u_mux2_mem_addr(.in0({look_line, look_mem_offset}), .in1(req_addr),
                                       .sel(unc_pass), .out(mem_req_addr));
    Mux2 #(3) u_mux2_mem_size(.in0(look_mem_size), .in1(req_size), .sel(unc_pass),
                              .out(mem_req_size));

    // See the behave version.
    `DC_ASSERT(a_unc_exact, !(unc_pass || (accept && (req_nocache || is_atomic(req_atop)))) ||
        (int'(req_size) <= SETS_OFFSET &&
         (req_addr & ((ADDR_WIDTH'(1) << req_size) - ADDR_WIDTH'(1))) == '0))
    `DC_ASSERT(a_atomic_load, !(req_valid && is_atomic(req_atop) && req_we))

    // The logic only stores, atomics and CBOs need; a read-only cache has none of it. Both
    // branches drive look_we, look_atomic, look_drops, store_write, merged, ram_wr_line and
    // the fields of a memory write (mem_req_we, mem_req_wdata, mem_req_wstrb), mem_req_atop
    // and mem_req_cmo.
    // @kb: rtl/lib/block/cache/read_only
    if (READ_ONLY) begin: g_read_only
        assign look_we     = 1'b0;
        assign look_atomic = 1'b0;
        assign look_drops  = 1'b0;
        assign store_write = 1'b0;
        assign merged      = '0;
        assign ram_wr_line = mem_rsp_data;

        assign mem_req_we    = 1'b0;
        assign mem_req_wdata = '0;
        assign mem_req_wstrb = '0;
        assign mem_req_atop  = ATOP_NONE;
        assign mem_req_cmo   = CMO_NONE;
    end else begin: g_store
        wire [STORE_WIDTH-1:0] look_store;      // {we, wdata, wstrb, atop, cmo} of the lookup
        wire [DATA_WIDTH-1:0]  look_wdata;
        wire [STRB_WIDTH-1:0]  look_wstrb;
        // Only its kind (bits [5:4]) is read here; all of it goes to memory in look_store.
        /* verilator lint_off UNUSEDSIGNAL */
        atop_t                 look_atop;
        /* verilator lint_on UNUSEDSIGNAL */
        cmo_t                  look_cmo;
        wire                   look_cbo;        // the lookup is a CBO
        wire                   cbo_n;
        wire                   hit_taken;       // a store that hits, taken by memory

        // The fields of the store, atomic or CBO taken, kept for its lookup.
        DffEn #(STORE_WIDTH) u_dff_en_store(
            .clk, .en(accept), .in({req_we, req_wdata, req_wstrb, req_atop, req_cmo}),
            .out(look_store));
        assign {look_we, look_wdata, look_wstrb, look_atop, look_cmo} = look_store;
        OrReduce #(2) u_or_reduce_atomic(.in(look_atop[5:4]), .out(look_atomic));
        OrReduce #(2) u_or_reduce_cbo(.in(look_cmo), .out(look_cbo));
        assign look_drops = look_cmo[1];                // CMO_INVAL, CMO_FLUSH

        // A memory write, an atomic's operand, a CBO: an uncached request's as it comes, else
        // the lookup's.
        Mux2 #(STORE_WIDTH) u_mux2_mem_store(
            .in0(look_store), .in1({req_we, req_wdata, req_wstrb, req_atop, req_cmo}),
            .sel(unc_pass), .out({mem_req_we, mem_req_wdata, mem_req_wstrb, mem_req_atop,
                                  mem_req_cmo}));

        // Store: the bytes of its strobes into the line, written when memory takes the store
        // (a CBO writes none).
        for (genvar b = 0; b < STRB_WIDTH; b++) begin: g_byte
            Mux2 #(8) u_mux2_byte(.in0(hit_line[8*b +: 8]), .in1(look_wdata[8*b +: 8]),
                                  .sel(look_wstrb[b]), .out(merged[8*b +: 8]));
        end
        And3 #(1) u_and3_hit_taken(.in1(store), .in2(hit), .in3(mem_req_ready), .out(hit_taken));
        Inv  #(1) u_inv_cbo(.in(look_cbo), .out(cbo_n));
        And2 #(1) u_and2_store_write(.in1(hit_taken), .in2(cbo_n), .out(store_write));
        Mux2 #(DATA_WIDTH) u_mux2_ram_wr(.in0(merged), .in1(mem_rsp_data), .sel(refill),
                                         .out(ram_wr_line));

        // See the behave version.
        `DC_ASSERT(a_cbo_store, !(req_valid && req_cmo != CMO_NONE && (!req_we ||
                                                                       req_wstrb != '0)))
    end

    // Load miss served from the clock memory takes its read until the answer comes. An
    // atomic drops the line it hits then; an inval or flush when memory takes it.
    And2 #(1) u_and2_served    (.in1(load_miss), .in2(mem_req_ready), .out(served));
    And2 #(1) u_and2_miss_taken(.in1(served), .in2(exact_n), .out(miss_taken));
    And3 #(1) u_and3_atomic_drop(.in1(served), .in2(look_atomic), .in3(hit), .out(atomic_drop));
    And2 #(1) u_and2_cbo_drop  (.in1(store), .in2(look_drops), .out(cbo_drop));
    And3 #(1) u_and3_cbo_drop_now(.in1(cbo_drop), .in2(hit), .in3(mem_req_ready),
                                  .out(cbo_drop_now));
    Or2  #(1) u_or2_drop       (.in1(atomic_drop), .in2(cbo_drop_now), .out(drop));
    Inv  #(1) u_inv_rsp        (.in(mem_rsp_valid), .out(mem_rsp_n));
    And2 #(1) u_and2_kept      (.in1(waiting), .in2(mem_rsp_n), .out(waiting_kept));
    Or2  #(1) u_or2_wait       (.in1(served), .in2(waiting_kept), .out(waiting_next));
    DffSyncRst #(.WIDTH(1)) u_dff_sync_rst_wait(.clk, .rst_n, .in(waiting_next), .out(waiting));
    And2 #(1) u_and2_answer    (.in1(waiting), .in2(mem_rsp_valid), .out(answer));
    DffEn #(1) u_dff_en_wait_nocache(.clk, .en(served), .in(look_exact),
                                     .out(wait_nocache));
    Inv  #(1) u_inv_wait_nocache(.in(wait_nocache), .out(wait_cache));
    And2 #(1) u_and2_refill    (.in1(answer), .in2(wait_cache), .out(refill));

    // Replay (see the behave version).
    // @kb: rtl/lib/block/cache/cache_control/refill_take
    // @kb: rtl/lib/block/cache/cache_control/replay
    And3 #(1) u_and3_replay(.in1(accept), .in2(refill), .in3(fill_conflict), .out(replay_next));
    DffSyncRst #(.WIDTH(1)) u_dff_sync_rst_replay(.clk, .rst_n, .in(replay_next), .out(replay));
    Or2  #(1) u_or2_ram_rd (.in1(accept), .in2(replay), .out(ram_rd));
    `DC_ASSERT_NEXT(a_replay_one_clock, replay, look_ok)

    // See the behave version.
    `DC_ASSERT(a_no_look_while_waiting, !(look && waiting))

    // A lookup whose memory request is not taken offers it again, unchanged, in the next
    // clock (held: the lookup and the RAM outputs stay). Not uncached requests: they
    // follow the CPU side, which may withdraw (kb rtl/lib/block/cache/uncached).
    `DC_ASSERT_NEXT(a_look_req_held, look_req && !mem_req_ready,
                    look_req && $stable(mem_req_addr) && $stable(mem_req_we) &&
                    $stable(mem_req_atop) && $stable(mem_req_cmo) &&
                    ((!mem_req_we && !is_atomic(mem_req_atop)) ||
                     ($stable(mem_req_wdata) && $stable(mem_req_wstrb))))

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

    Or3  #(1)          u_or3_rsp    (.in1(load_hit), .in2(answer), .in3(unc_rsp), .out(rsp_valid));
    Or2  #(1)          u_or2_rsp_mem(.in1(waiting), .in2(unc_waiting), .out(rsp_mem));
    Mux2 #(DATA_WIDTH) u_mux2_data  (.in0(hit_line), .in1(mem_rsp_data), .sel(rsp_mem),
                                     .out(rsp_data));

endmodule

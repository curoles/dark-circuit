/* Mig3 caches: the instruction cache and the data cache, between the pipeline and the one
 * memory port of Mig3Core.
 *
 * Both are skewed-associative caches of the library (rtl/lib/block/cache), 2 ways of lines
 * of LINE_WORDS words (Mig3Pkg, cfg cache_line_words; both caches and the memory move lines
 * of one size): the I-cache SkewedCacheRdOnly, 1 << CFG.icache_sets_width lines a way; the
 * D-cache SkewedCache, 1 << CFG.dcache_sets_width lines a way, write-through, no
 * write-allocate. Their CPU side is a channel of Mig3Pkg (imem_req_t from fetch, dmem_req_t
 * from the load/store unit, and their answers), one word; a fetch gets the whole line the
 * cache answers (Mig3Fetch selects the word and keeps the line, kb
 * rtl/design/mig3/fetch_line), a load takes its word of the line (the word index of the
 * request, kept when the cache takes it); a store writes its word into every word of the
 * line, with its strobes only in its own. A hit answers in the clock after the request, as a
 * memory of latency 1; a miss asks memory for the line and answers when it comes; a store
 * goes to memory in any case; so does a CBO (Zicbom: a store of no bytes with its cmo), and
 * an inval or flush drops the line it hits (kb rtl/lib/block/cache/cbo). Their memory sides
 * share one memory through
 * InsnDataCacheArbiter (u_arbiter): when both ask, the instruction cache first while prio
 * says so (Mig3Core: while ID has no instruction, every stage starves), else the data cache
 * (a load that waits stalls every stage); each side's request goes through the arbiter's
 * flow-through buffer, so neither cache sees memory's ready or the other cache's valid
 * without a flop (kb pattern rtl/lib/block/flow_through_buffer/design). uncached=1 makes
 * every request bypass both caches: it passes to the arbiter as it comes (req_uncached_dbg_bypass
 * of
 * the library caches: exactly its bytes, address and size), so the pipeline sees the memory's
 * own
 * timing, but for a fetch and a load or store that want memory in the same clock (tests that
 * count cycles). A load or store of the I/O region (CFG.io_base, 1 << CFG.io_addr_width
 * bytes) is never cached (req_nocache: looked up, never a hit or a fill); code is never
 * fetched from it. invalidate is 0:
 * Mig3 has no FENCE.I; a store to an address the I-cache
 * holds is not seen by a later fetch that hits (self-modifying code is not supported).
 *
 *   icache_req (fetch) --> word in line --> SkewedCacheRdOnly u_icache --+
 *                      <-- line <--------                                +--> InsnDataCache-
 *   dcache_req (lsu) ----> word in line --> SkewedCache u_dcache --------+    Arbiter --> mem_req
 *                      <-- word of line <--                                   u_arbiter <-- mem_rsp
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
`include "dark_circuit_assert.svh"

module Mig3Caches import Mig3Pkg::*; #(
    parameter mig3_cfg_t CFG = MIG3_CFG     // configuration, see Mig3ConfigPkg
)(
    input  wire       clk,
    input  wire       rst_n,            // synchronous reset, active low
    input  wire       uncached,         // every request bypasses the caches
    input  wire [1:0] prio,             // the arbiter's tie (CachePkg): PRIO_INSN or none

    // Pipeline side: fetch and the load/store unit, one word
    input  imem_req_t icache_req,
    output imem_rsp_t icache_rsp,
    input  dmem_req_t dcache_req,
    output dmem_rsp_t dcache_rsp,

    // Memory side: the memory port of Mig3Core, one line
    output mem_req_t  mem_req,
    input  mem_rsp_t  mem_rsp
);
    `DC_STATIC_ASSERT(a_line_words, LINE_WORDS == 1 || LINE_WORDS == 2)
    `DC_STATIC_ASSERT(a_io_aligned, CFG.io_base % (1 << CFG.io_addr_width) == 0)

    // A load or store of the I/O region is never cached: a device's register is read and
    // written where it is, every time (a PLIC claim is a read). req_nocache acts in the
    // D-cache's lookup, through a register: the address compare is not on the path to
    // req_ready and EX's stall.
    // @kb: rtl/design/mig3/io_region
    logic d_io;         // the data request is in the I/O region
    assign d_io =
        dcache_req.addr[WIDTH-1:CFG.io_addr_width] == CFG.io_base[WIDTH-1:CFG.io_addr_width];

    // The caches' memory sides, to the arbiter: byte addresses, a line's (offset 0) or an
    // uncached request's own, with its size.
    logic             i_mem_valid;
    logic             i_mem_ready;
    logic [WIDTH-1:0] i_mem_addr;
    logic [2:0]       i_mem_size;
    logic             i_mem_rsp_valid;
    line_t            i_mem_rsp_data;
    logic             d_mem_valid;
    logic             d_mem_ready;
    logic             d_mem_we;
    logic [WIDTH-1:0] d_mem_addr;
    logic [2:0]       d_mem_size;
    line_t            d_mem_wdata;
    line_strb_t       d_mem_wstrb;
    AtomicPkg::atop_t d_mem_atop;
    CachePkg::cmo_t   d_mem_cmo;
    logic             d_mem_rsp_valid;
    line_t            d_mem_rsp_data;
    // The caches' CPU sides, lines.
    line_t            i_line;           // the I-cache's answer
    line_t            d_line;           // the D-cache's answer
    line_t            d_wdata;          // a store's word in every word of the line
    line_strb_t       d_wstrb;          // its strobes in its own word

    // @kb: rtl/design/mig2/caches_in_core
    SkewedCacheRdOnly #(.ADDR_WIDTH(WIDTH), .SETS_WIDTH(CFG.icache_sets_width),
                        .SETS_OFFSET(LINE_START)) u_icache(
        .clk, .rst_n, .invalidate(1'b0),
        .req_valid(icache_req.valid), .req_addr({icache_req.addr, {IADDR_START{1'b0}}}),
        .req_uncached_dbg_bypass(uncached), .req_size(SIZE_W), .req_nocache(1'b0),
        .req_ready(icache_rsp.ready),
        .rsp_valid(icache_rsp.valid), .rsp_data(i_line),
        .mem_req_valid(i_mem_valid), .mem_req_ready(i_mem_ready),
        .mem_req_addr(i_mem_addr), .mem_req_size(i_mem_size),
        .mem_rsp_valid(i_mem_rsp_valid),
        .mem_rsp_data(i_mem_rsp_data));

    SkewedCache #(.ADDR_WIDTH(WIDTH), .SETS_WIDTH(CFG.dcache_sets_width),
                  .SETS_OFFSET(LINE_START)) u_dcache(
        .clk, .rst_n, .invalidate(1'b0),
        .req_valid(dcache_req.valid), .req_ready(dcache_rsp.ready),
        .req_uncached_dbg_bypass(uncached),
        .req_we(dcache_req.we), .req_addr({dcache_req.addr, dcache_req.offset}),
        .req_wdata(d_wdata), .req_wstrb(d_wstrb), .req_size(dcache_req.size),
        .req_nocache(d_io), .req_atop(dcache_req.atop),
        .req_cmo(dcache_req.cmo),
        .rsp_valid(dcache_rsp.valid), .rsp_data(d_line),
        .mem_req_valid(d_mem_valid), .mem_req_ready(d_mem_ready),
        .mem_req_we(d_mem_we), .mem_req_addr(d_mem_addr),
        .mem_req_wdata(d_mem_wdata), .mem_req_wstrb(d_mem_wstrb), .mem_req_size(d_mem_size),
        .mem_req_atop(d_mem_atop), .mem_req_cmo(d_mem_cmo),
        .mem_rsp_valid(d_mem_rsp_valid), .mem_rsp_data(d_mem_rsp_data));

    // A fetch gets the line (fetch selects its word, after a register: kb
    // rtl/design/mig3/fetch_line).
    assign icache_rsp.data = i_line;

    // The data side is one word: a load takes its word of the line, a store writes its
    // word into every word of the line, with its strobes in its own.
    // @kb: rtl/design/mig3/cache_lines
    if (LINE_WORDS == 1) begin: g_one_word
        assign dcache_rsp.data = d_line;
        assign d_wdata         = dcache_req.wdata;
        assign d_wstrb         = dcache_req.wstrb;
    end else begin: g_words
        localparam WORD_BITS = $clog2(LINE_WORDS);
        word_t [LINE_WORDS-1:0] d_words;        // the answer as words
        logic  [WORD_BITS-1:0]  d_word;         // the word of the answer: the request's

        // The answer comes a clock after the request is taken, or later; the next request is
        // taken at that edge at the earliest, so the index kept still belongs to the answer.
        always_ff @(posedge clk)
            if (dcache_req.valid && dcache_rsp.ready)
                d_word <= dcache_req.addr[LINE_START-1:DADDR_START];

        assign d_words         = d_line;
        assign dcache_rsp.data = d_words[d_word];
        assign d_wdata         = {LINE_WORDS{dcache_req.wdata}};
        assign d_wstrb         = line_strb_t'(dcache_req.wstrb)
                                 << (STRB_WIDTH * dcache_req.addr[LINE_START-1:DADDR_START]);
    end

    // @kb: rtl/design/mig2/single_memory
    // A tie: prio's side, else the data cache (the package name: Icarus takes an imported
    // name alone as a port expression for an implicit wire).
    InsnDataCacheArbiter #(.ADDR_WIDTH(WIDTH), .DATA_WIDTH($bits(line_t)),
                           .POLICY(CachePkg::ARB_DATA_FIRST)) u_arbiter(
        .clk, .rst_n, .prio,
        .icache_req_valid(i_mem_valid), .icache_req_ready(i_mem_ready),
        .icache_req_addr(i_mem_addr), .icache_req_size(i_mem_size),
        .icache_rsp_valid(i_mem_rsp_valid),
        .icache_rsp_data(i_mem_rsp_data),
        .dcache_req_valid(d_mem_valid), .dcache_req_ready(d_mem_ready), .dcache_req_we(d_mem_we),
        .dcache_req_addr(d_mem_addr), .dcache_req_wdata(d_mem_wdata),
        .dcache_req_wstrb(d_mem_wstrb), .dcache_req_size(d_mem_size),
        .dcache_req_atop(d_mem_atop), .dcache_req_cmo(d_mem_cmo),
        .dcache_rsp_valid(d_mem_rsp_valid),
        .dcache_rsp_data(d_mem_rsp_data),
        .mem_req_valid(mem_req.valid), .mem_req_ready(mem_rsp.ready), .mem_req_we(mem_req.we),
        .mem_req_addr(mem_req.addr), .mem_req_wdata(mem_req.wdata),
        .mem_req_wstrb(mem_req.wstrb), .mem_req_size(mem_req.size),
        .mem_req_atop(mem_req.atop), .mem_req_cmo(mem_req.cmo),
        .mem_rsp_valid(mem_rsp.valid),
        .mem_rsp_data(mem_rsp.data));


endmodule

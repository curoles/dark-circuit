/* Mig2 caches: the instruction cache and the data cache, between the pipeline and the one
 * memory port of Mig2Core.
 *
 * Both are skewed-associative caches of the library (rtl/lib/block/cache), 2 ways of one-word
 * lines: the I-cache SkewedCacheRdOnly, 1 << CFG.icache_sets_width lines a way; the D-cache
 * SkewedCache, 1 << CFG.dcache_sets_width lines a way, write-through, no write-allocate.
 * Their CPU side is a channel of Mig2Pkg (imem_req_t from fetch, mem_req_t from the load/store
 * unit, and their answers): a hit answers in the clock after the request, as a memory of
 * latency 1; a miss asks memory for the word and answers when it comes; a store goes to
 * memory in any case. Their memory sides share one memory through InsnDataCacheArbiter
 * (u_arbiter): when both ask, the instruction cache first while prio says so (Mig2Core:
 * while ID has no instruction, every stage starves), else the data cache (a load that
 * waits stalls every stage); each side's request goes through the
 * arbiter's flow-through buffer, so neither cache sees memory's ready or the other cache's
 * valid without a flop (kb pattern rtl/lib/block/flow_through_buffer/design). uncached=1
 * makes every request bypass both caches: it passes to the arbiter as it comes
 * (req_uncached of the library caches), so the pipeline sees the memory's own timing, but
 * for a fetch and a load or store that want memory in the same clock (tests that count
 * cycles). invalidate is 0: Mig2 has no FENCE.I; a store to an address the I-cache holds is
 * not seen by a later fetch that hits (self-modifying code is not supported).
 *
 *   icache_req (fetch) --> SkewedCacheRdOnly u_icache --+
 *                                                       +--> InsnDataCacheArbiter --> mem_req
 *   dcache_req (lsu) ----> SkewedCache u_dcache --------+    u_arbiter (prio, else  <-- mem_rsp
 *                                                                   data first)
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module Mig2Caches import Mig2Pkg::*; #(
    parameter mig2_cfg_t CFG = MIG2_CFG     // configuration, see Mig2ConfigPkg
)(
    input  wire       clk,
    input  wire       rst_n,            // synchronous reset, active low
    input  wire       uncached,         // every request bypasses the caches
    input  wire [1:0] prio,             // the arbiter's tie (CachePkg): PRIO_INSN or none

    // Pipeline side: fetch and the load/store unit
    input  imem_req_t icache_req,
    output imem_rsp_t icache_rsp,
    input  mem_req_t  dcache_req,
    output mem_rsp_t  dcache_rsp,

    // Memory side: the memory port of Mig2Core
    output mem_req_t  mem_req,
    input  mem_rsp_t  mem_rsp
);
    // The caches' memory sides, to the arbiter: byte addresses of words (offset 0).
    logic             i_mem_valid;
    logic             i_mem_ready;
    logic [WIDTH-1:0] i_mem_addr;
    logic [2:0]       i_mem_size;
    logic             i_mem_rsp_valid;
    insn_t            i_mem_rsp_data;
    logic             d_mem_valid;
    logic             d_mem_ready;
    logic             d_mem_we;
    logic [WIDTH-1:0] d_mem_addr;
    logic [2:0]       d_mem_size;
    word_t            d_mem_wdata;
    strb_t            d_mem_wstrb;
    logic             d_mem_rsp_valid;
    word_t            d_mem_rsp_data;
    // The word address goes to the memory port: the offset of the byte address is 0.
    /* verilator lint_off UNUSEDSIGNAL */
    logic [WIDTH-1:0] mem_byte_addr;
    logic [2:0]       mem_size;          // the request's size: not on the port yet
    /* verilator lint_on UNUSEDSIGNAL */

    // @kb: rtl/design/mig2/caches_in_core
    SkewedCacheRdOnly #(.ADDR_WIDTH(WIDTH), .SETS_WIDTH(CFG.icache_sets_width),
                        .SETS_OFFSET(IADDR_START)) u_icache(
        .clk, .rst_n, .invalidate(1'b0),
        .req_valid(icache_req.valid), .req_addr({icache_req.addr, {IADDR_START{1'b0}}}),
        .req_uncached(uncached), .req_size(3'd2), .req_ready(icache_rsp.ready),
        .rsp_valid(icache_rsp.valid), .rsp_data(icache_rsp.data),
        .mem_req_valid(i_mem_valid), .mem_req_ready(i_mem_ready),
        .mem_req_addr(i_mem_addr), .mem_req_size(i_mem_size),
        .mem_rsp_valid(i_mem_rsp_valid),
        .mem_rsp_data(i_mem_rsp_data));

    SkewedCache #(.ADDR_WIDTH(WIDTH), .SETS_WIDTH(CFG.dcache_sets_width),
                  .SETS_OFFSET(DADDR_START)) u_dcache(
        .clk, .rst_n, .invalidate(1'b0),
        .req_valid(dcache_req.valid), .req_ready(dcache_rsp.ready), .req_uncached(uncached),
        .req_we(dcache_req.we), .req_addr({dcache_req.addr, {DADDR_START{1'b0}}}),
        .req_wdata(dcache_req.wdata), .req_wstrb(dcache_req.wstrb), .req_size(3'd2),
        .rsp_valid(dcache_rsp.valid), .rsp_data(dcache_rsp.data),
        .mem_req_valid(d_mem_valid), .mem_req_ready(d_mem_ready),
        .mem_req_we(d_mem_we), .mem_req_addr(d_mem_addr),
        .mem_req_wdata(d_mem_wdata), .mem_req_wstrb(d_mem_wstrb), .mem_req_size(d_mem_size),
        .mem_rsp_valid(d_mem_rsp_valid), .mem_rsp_data(d_mem_rsp_data));

    // @kb: rtl/design/mig2/single_memory
    // A tie: prio's side, else the data cache (the package name: Icarus takes an imported
    // name alone as a port expression for an implicit wire).
    InsnDataCacheArbiter #(.ADDR_WIDTH(WIDTH), .DATA_WIDTH($bits(word_t)),
                           .POLICY(CachePkg::ARB_DATA_FIRST)) u_arbiter(
        .clk, .rst_n, .prio,
        .icache_req_valid(i_mem_valid), .icache_req_ready(i_mem_ready),
        .icache_req_addr(i_mem_addr), .icache_req_size(i_mem_size),
        .icache_rsp_valid(i_mem_rsp_valid),
        .icache_rsp_data(i_mem_rsp_data),
        .dcache_req_valid(d_mem_valid), .dcache_req_ready(d_mem_ready), .dcache_req_we(d_mem_we),
        .dcache_req_addr(d_mem_addr), .dcache_req_wdata(d_mem_wdata),
        .dcache_req_wstrb(d_mem_wstrb), .dcache_req_size(d_mem_size),
        .dcache_rsp_valid(d_mem_rsp_valid),
        .dcache_rsp_data(d_mem_rsp_data),
        .mem_req_valid(mem_req.valid), .mem_req_ready(mem_rsp.ready), .mem_req_we(mem_req.we),
        .mem_req_addr(mem_byte_addr), .mem_req_wdata(mem_req.wdata),
        .mem_req_wstrb(mem_req.wstrb), .mem_req_size(mem_size),
        .mem_rsp_valid(mem_rsp.valid),
        .mem_rsp_data(mem_rsp.data));

    assign mem_req.addr = mem_byte_addr[WIDTH-1:DADDR_START];

endmodule

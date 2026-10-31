/* Mig2 caches: the instruction cache and the data cache, between the pipeline and the memory
 * ports of Mig2Core.
 *
 * Both are skewed-associative caches of the library (rtl/lib/block/cache), 2 ways of one-word
 * lines: the I-cache SkewedCacheRdOnly, 1 << CFG.icache_sets_width lines a way; the D-cache
 * SkewedCache, 1 << CFG.dcache_sets_width lines a way, write-through, no write-allocate.
 * Their CPU side and their memory side are the channels of Mig2Pkg (imem_req_t, dmem_req_t
 * and their answers): a hit answers in the clock after the request, as a memory of latency 1;
 * a miss asks the memory port for the word and answers when it comes; a store goes to the
 * memory port in any case. uncached=1 makes every request bypass both caches: it passes to
 * the memory port as it comes (req_uncached of the library caches), so the pipeline sees the
 * memories' own timing (tests that count cycles). invalidate is 0: Mig2 has no FENCE.I, and
 * its instruction memory is not written.
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

    // Pipeline side: fetch and the load/store unit
    input  imem_req_t icache_req,
    output imem_rsp_t icache_rsp,
    input  dmem_req_t dcache_req,
    output dmem_rsp_t dcache_rsp,

    // Memory side: the memory ports of Mig2Core
    output imem_req_t imem_req,
    input  imem_rsp_t imem_rsp,
    output dmem_req_t dmem_req,
    input  dmem_rsp_t dmem_rsp
);
    // Byte addresses of the words memory is asked for: their offset is 0.
    /* verilator lint_off UNUSEDSIGNAL */
    logic [WIDTH-1:0] imem_byte_addr;
    logic [WIDTH-1:0] dmem_byte_addr;
    /* verilator lint_on UNUSEDSIGNAL */

    // @kb: rtl/design/mig2/caches_in_core
    SkewedCacheRdOnly #(.ADDR_WIDTH(WIDTH), .SETS_WIDTH(CFG.icache_sets_width),
                        .SETS_OFFSET(IADDR_START)) u_icache(
        .clk, .rst_n, .invalidate(1'b0),
        .req_valid(icache_req.valid), .req_addr({icache_req.addr, {IADDR_START{1'b0}}}),
        .req_uncached(uncached), .req_ready(icache_rsp.ready),
        .rsp_valid(icache_rsp.valid), .rsp_data(icache_rsp.data),
        .mem_req_valid(imem_req.valid), .mem_req_ready(imem_rsp.ready),
        .mem_req_addr(imem_byte_addr), .mem_rsp_valid(imem_rsp.valid),
        .mem_rsp_data(imem_rsp.data));

    assign imem_req.addr = imem_byte_addr[WIDTH-1:IADDR_START];

    SkewedCache #(.ADDR_WIDTH(WIDTH), .SETS_WIDTH(CFG.dcache_sets_width),
                  .SETS_OFFSET(DADDR_START)) u_dcache(
        .clk, .rst_n, .invalidate(1'b0),
        .req_valid(dcache_req.valid), .req_ready(dcache_rsp.ready), .req_uncached(uncached),
        .req_we(dcache_req.we), .req_addr({dcache_req.addr, {DADDR_START{1'b0}}}),
        .req_wdata(dcache_req.wdata), .req_wstrb(dcache_req.wstrb),
        .rsp_valid(dcache_rsp.valid), .rsp_data(dcache_rsp.data),
        .mem_req_valid(dmem_req.valid), .mem_req_ready(dmem_rsp.ready),
        .mem_req_we(dmem_req.we), .mem_req_addr(dmem_byte_addr),
        .mem_req_wdata(dmem_req.wdata), .mem_req_wstrb(dmem_req.wstrb),
        .mem_rsp_valid(dmem_rsp.valid), .mem_rsp_data(dmem_rsp.data));

    assign dmem_req.addr = dmem_byte_addr[WIDTH-1:DADDR_START];

endmodule

/* Mig6 PE (processing element), for simulation: one Mig6Core, its local memory and its
 * network interface.
 *
 * A prototype (rtl/design/mig6/README.md). The local memory is the code and data of the
 * program, private to the core: a SimLatencyRAM behind the core's memory port (latency 1,
 * always ready), as Mig3Cpu's memory without its devices; the core's caches are in front of
 * it, so it is not a scratchpad (a memory without caches before it). The network interface
 * (Mig6PeNetIf) takes the core's accesses to the shared memory onto the NoC: the PE's four
 * noc_* ports, joined by Mig6PeGrid to the meshes' local ports of the PE's node. HART_ID is
 * the hart's ID, what mhartid reads, one per PE; MY_PE_GRID_X and MY_PE_GRID_Y are the PE's
 * node in the mesh, what mnodeid reads and the network interface's coordinates.
 *
 * Where an access goes is the memory map's (Mig6PmaPkg, cfg/mig6_pma.yaml): its region's
 * target, local or net. ReqDemux sends it there and keeps the answers in order (an access
 * to the other target waits until the reads before it are answered). The local memory is
 * the region local, at its base, where programs start (CFG.rst_addr: a_reset_in_local). The
 * shared memory is never cached, so only accesses of a word or less go to the network
 * interface, in the core's line-wide format: the word the address names is picked from the
 * line (a store's word is in every word of the line, its strobes only in its own; an AMO's
 * operand in every word), and the answer goes into every word of the line, as Mig3Cpu does
 * for its devices.
 *
 * Checked by assertions, with the regions' attributes: every access is in a region
 * (a_in_region; later an access fault); none goes to the devices' region, as a PE has no
 * devices yet (a_no_devices); no AMO goes to a region without atomics (a_atomics_allowed:
 * the local memory has no AtomicUnit in front of it; LR/SC are the core's own).
 *
 *   Mig6Core --mem_req--> pma_of: target --> ReqDemux --+--> u_local_mem (SimLatencyRAM)
 *            <--mem_rsp--------------------------------- |
 *                                                        +--> word pick --> u_net_if
 *                                                             <-- answer in every word
 *                                                        u_net_if <==> noc_req_*, noc_rsp_*
 *
 * load() puts the hex image (objcopy -O verilog, see sw/riscv/mig6/mig6.ld) into the local
 * memory; peek() reads a byte of it, for the testbench's semihosting.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "dark_circuit_assert.svh"

module Mig6Pe import Mig6Pkg::*; #(
    parameter mig6_cfg_t CFG     = MIG6_CFG,    // configuration, see Mig6ConfigPkg
    parameter word_t     HART_ID = '0,          // the hart's ID: mhartid
    // Its node in the mesh: mnodeid, and its network interface's coordinates.
    parameter logic [Mig6NocPkg::X_WIDTH-1:0] MY_PE_GRID_X = '0,
    parameter logic [Mig6NocPkg::Y_WIDTH-1:0] MY_PE_GRID_Y = '0,
    parameter            NOC_BUF_DEPTH = 4      // the routers' input buffers: credits
)(
    input  wire                       clk,
    input  wire                       rst_n,           // synchronous reset, active low
    output wire                       halt,            // core halted at EBREAK, see Mig6Core
    output retire_t                   retire,          // for trace in testbench
    output pipe_trace_t               pipe_trace,      // pipeline view for testbench
    input  dbg_req_t                  dbg_req,         // debug, used while halted
    output dbg_rsp_t                  dbg_rsp,
    // The meshes' local ports of the PE's node (Mig6NocPkg)
    output Mig6NocPkg::req_link_fwd_t noc_req_fwd,     // requests to the request mesh
    input  Mig6NocPkg::link_bwd_t     noc_req_bwd,     //   its credits
    input  Mig6NocPkg::rsp_link_fwd_t noc_rsp_fwd,     // answers from the answer mesh
    output Mig6NocPkg::link_bwd_t     noc_rsp_bwd      //   credits to it
);
    localparam MEM_ADDR_WIDTH = Mig6PmaPkg::LOCAL_ADDR_WIDTH;   // local memory: 1 << it bytes
    localparam LOCAL = 0;           // ReqDemux's targets
    localparam NET   = 1;

    // Programs are linked to start at the local memory's base (sw/riscv/mig6/mig6.ld).
    `DC_STATIC_ASSERT(a_reset_in_local, CFG.rst_addr == Mig6PmaPkg::LOCAL_BASE)

    mem_req_t         mem_req;
    mem_rsp_t         mem_rsp;
    // Of the region's attributes the cache's (cacheable) and the later ones (io, reservable)
    // are not read here.
    /* verilator lint_off UNUSEDSIGNAL */
    Mig6PmaPkg::pma_t mem_pma;      // the request's region
    /* verilator lint_on UNUSEDSIGNAL */
    logic [1:0]       sel;          // one-hot: the request's target, NET or LOCAL
    logic [1:0]       tgt_valid;
    logic [1:0]       tgt_ready;
    logic [1:0]       tgt_rsp_valid;
    line_t            local_rsp_data;
    word_t            net_wdata;    // the word of the line the address names
    strb_t            net_wstrb;
    word_t            net_rsp_data;

    Mig6Core #(.CFG(CFG), .HART_ID(HART_ID), .MY_PE_GRID_X(8'(MY_PE_GRID_X)),
               .MY_PE_GRID_Y(8'(MY_PE_GRID_Y))) u_mig6_core(
        .clk, .rst_n, .mem_req, .mem_rsp, .uncached(1'b0), .meip(1'b0), .halt, .retire,
        .pipe_trace, .dbg_req, .dbg_rsp);

    // Where the request goes: its region's target (an access in no region, or to the
    // devices, stops the run below; it goes to the local memory meanwhile).
    assign mem_pma    = Mig6PmaPkg::pma_of(mem_req.addr);
    assign sel[NET]   = mem_pma.hit && mem_pma.target == Mig6PmaPkg::TARGET_NET;
    assign sel[LOCAL] = !sel[NET];

    ReqDemux #(.N_TARGETS(2), .RSP_WIDTH($bits(line_t))) u_req_demux(
        .clk, .rst_n,
        .req_valid(mem_req.valid), .req_ready(mem_rsp.ready), .req_rsp(!mem_req.we),
        .req_sel(sel), .rsp_valid(mem_rsp.valid), .rsp_data(mem_rsp.data),
        .tgt_req_valid(tgt_valid), .tgt_req_ready(tgt_ready), .tgt_rsp_valid(tgt_rsp_valid),
        .tgt_rsp_data({{LINE_WORDS{net_rsp_data}}, local_rsp_data}));

    // The local memory, code and data; latency 1, always ready.
    SimLatencyRAM #(.DATA_SIZE(LINE_SIZE), .ADDR_WIDTH(MEM_ADDR_WIDTH),
                    .READY_PERCENT(100), .FAST_PERCENT(100), .FAST_MIN(1), .FAST_MAX(1),
                    .MAX_PENDING(1)) u_local_mem(
        .clk, .rst_n,
        .req_valid(tgt_valid[LOCAL]), .req_ready(tgt_ready[LOCAL]), .req_we(mem_req.we),
        .req_addr({mem_req.addr[MEM_ADDR_WIDTH-1:LINE_START], {LINE_START{1'b0}}}),
        .req_wdata(mem_req.wdata), .req_wstrb(mem_req.wstrb),
        .rsp_valid(tgt_rsp_valid[LOCAL]), .rsp_data(local_rsp_data));

    // The network interface's word: the one of the line the address names (a store's word
    // is in every word, its strobes only in its own).
    if (LINE_WORDS == 1) begin: g_one_word
        assign net_wdata = mem_req.wdata;
        assign net_wstrb = mem_req.wstrb;
    end else begin: g_words
        word_t [LINE_WORDS-1:0] words;
        strb_t [LINE_WORDS-1:0] strbs;
        assign words     = mem_req.wdata;
        assign strbs     = mem_req.wstrb;
        assign net_wdata = words[mem_req.addr[LINE_START-1:DADDR_START]];
        assign net_wstrb = strbs[mem_req.addr[LINE_START-1:DADDR_START]];
    end

    Mig6PeNetIf #(.MY_PE_GRID_X(MY_PE_GRID_X), .MY_PE_GRID_Y(MY_PE_GRID_Y),
                  .BUF_DEPTH(NOC_BUF_DEPTH)) u_net_if(
        .clk, .rst_n,
        .req_valid(tgt_valid[NET]), .req_ready(tgt_ready[NET]), .req_we(mem_req.we),
        .req_addr(mem_req.addr), .req_size(mem_req.size), .req_atop(mem_req.atop),
        .req_cmo(mem_req.cmo), .req_excl(1'b0), .req_rsp(!mem_req.we),
        .req_wdata(net_wdata), .req_wstrb(net_wstrb),
        .rsp_valid(tgt_rsp_valid[NET]), .rsp_data(net_rsp_data),
        .noc_req_fwd, .noc_req_bwd, .noc_rsp_fwd, .noc_rsp_bwd);

    // The memory map: every access in a region; no devices in a PE yet; AMOs only where the
    // region has atomics (the shared memory's AtomicUnit; none in front of the local memory).
    `DC_ASSERT(a_in_region, !(mem_req.valid && !mem_pma.hit))
    `DC_ASSERT(a_no_devices, !(mem_req.valid && mem_pma.target == Mig6PmaPkg::TARGET_DEVICES))
    `DC_ASSERT(a_atomics_allowed,
               !(mem_req.valid && AtomicPkg::is_atomic(mem_req.atop) && !mem_pma.atomics))

    // Load the hex image into the local memory, returns 1 when it is loaded.
    function automatic int load(string hex);
        return u_local_mem.load(hex, u_local_mem.VLOG_HEX_FORMAT);
    endfunction

    // Byte at address a of the local memory (its offset in the region).
    function automatic logic [7:0] peek(input logic [MEM_ADDR_WIDTH-1:0] a);
        return u_local_mem.peek(a);
    endfunction

endmodule

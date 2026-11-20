/* Mig6 PE (processing element), for simulation: one Mig6Core, its local memory, its DMA and
 * its network interface.
 *
 * A prototype (rtl/design/mig6/README.md). The local memory is the code and data of the
 * program, private to the PE: a SimLatencyRAM (latency 1, always ready). It is a scratchpad
 * for data (kb rtl/design/mig6/scratchpad): the core's loads and stores to it come on the
 * core's data port (lmem), past the D-cache, answered in the clock after as a hit is.
 *
 * Two requesters, the core's memory port (the I-cache's misses, the D-cache's requests: far
 * ones and the DMA's registers) and the DMA's memory side, reach two targets, the local
 * memory and the network interface, through a crossbar of the library's channels (kb
 * rtl/design/mig6/dma): a ReqDemux for each requester, by its address's region (Mig6PmaPkg,
 * cfg/mig6_pma.yaml: target local, net or devices), and a ReqMux in front of each target. So
 * the core works on the local memory while the DMA waits for the network. The local
 * memory's ReqMux is by fixed priority, the core's data first (taken in the clock it comes:
 * Mig6Caches a_lmem_taken; kb rtl/lib/block/req_mux/fixed_priority), then the I-cache's
 * misses, then the DMA; the network interface's is round-robin, the core's requests and the
 * DMA's. The core's stores to the shared memory are in the network before a later DMA read
 * of them: both pass the one network interface, in order.
 *
 * The DMA is the library's DmaSifive (SiFive's PDMA map, sw/riscv/drivers/dma.h), its
 * registers the region dma (target devices), one channel per 4 KiB of it; the core polls
 * done (no interrupt yet: the PLIC is a later step). Its memory side is a word (the network
 * interface's), one transaction in flight (DmaEngine's mover): a word written to the local
 * memory goes into every word of the line, its strobes in its own; a word read from it is
 * picked from the line by the word index kept when the read was taken, right while the
 * local memory answers in the clock after (a_dma_local_next), however many reads the DMA
 * keeps in flight. The network interface takes a word: the core's word is the one of its
 * line the address names, and the answer goes into every word of the line, as for the
 * DMA's registers.
 *
 * Checked by assertions, with the regions' attributes: every access is in a region
 * (a_in_region; later an access fault); no AMO goes to a region without atomics
 * (a_atomics_allowed); the scratchpad gets no AMO and no exclusive request (a_lmem_plain: no
 * AtomicUnit in front of the local memory; LR/SC are the core's own); an exclusive request
 * goes to the network (a_excl_to_net); the DMA moves only between the local memory and the
 * network (a_dma_target). Not yet: the DMA's writes to the local memory do not end the
 * core's LR/SC reservation (a monitor at the local memory, a later step).
 *
 *   Mig6Core --lmem (data, local)-----------------------------> u_local_mux 0 --+
 *            --mem--> u_req_demux --local---------------------> u_local_mux 1   |
 *                                 --net ---> u_net_mux 0 --+                   |
 *                                 --devices: u_dma's regs  |   u_local_mux 2 --+
 *   u_dma (memory side) --> u_dma_demux --local---------------^                 |
 *                                       --net -> u_net_mux 1 --+          u_local_mem
 *                                                   u_net_if <==> noc_req_*, noc_rsp_*
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
    // The DMA's registers: the region dma, 4 KiB a channel (DmaSifivePkg::CHAN_BITS).
    localparam DMA_ADDR_WIDTH = Mig6PmaPkg::DMA_ADDR_WIDTH;
    localparam DMA_N          = 1 << (DMA_ADDR_WIDTH - DmaSifivePkg::CHAN_BITS);
    localparam LOCAL = 0;           // the requesters' targets
    localparam NET   = 1;
    localparam DMA   = 2;           // ... the core's only: the DMA's registers

    // Programs are linked to start at the local memory's base (sw/riscv/mig6/mig6.ld).
    `DC_STATIC_ASSERT(a_reset_in_local, CFG.rst_addr == Mig6PmaPkg::LOCAL_BASE)
    `DC_STATIC_ASSERT(a_dma_channels, DMA_ADDR_WIDTH >= DmaSifivePkg::CHAN_BITS)

    // The core's ports.
    mem_req_t         mem_req;
    mem_rsp_t         mem_rsp;
    // Of the scratchpad's requests the memory reads the line's address, data and strobes;
    // the assertions the operation.
    /* verilator lint_off UNUSEDSIGNAL */
    mem_req_t         lmem_req;
    /* verilator lint_on UNUSEDSIGNAL */
    mem_rsp_t         lmem_rsp;
    // Of the region's attributes the cache's (cacheable) and the later ones (io, reservable)
    // are not read here.
    /* verilator lint_off UNUSEDSIGNAL */
    Mig6PmaPkg::pma_t mem_pma;      // the core's request's region
    Mig6PmaPkg::pma_t dma_pma;      // the DMA's request's region
    /* verilator lint_on UNUSEDSIGNAL */
    logic [2:0]       sel;          // one-hot: the core's request's target
    logic [2:0]       tgt_valid;
    logic [2:0]       tgt_ready;
    logic [2:0]       tgt_rsp_valid;
    word_t            core_wdata;   // the word of the core's line the address names
    strb_t            core_wstrb;

    // The DMA.
    wire              dma_reg_ready;
    word_t            dma_rdata;
    /* verilator lint_off UNUSEDSIGNAL */
    wire [2*DMA_N-1:0] dma_irq;     // polled: no interrupt yet
    /* verilator lint_on UNUSEDSIGNAL */
    wire              dma_mem_valid;
    wire              dma_mem_ready;
    wire              dma_mem_we;
    word_t            dma_mem_addr;
    size_t            dma_mem_size;
    word_t            dma_mem_wdata;
    strb_t            dma_mem_wstrb;
    wire              dma_mem_rsp_valid;
    word_t            dma_mem_rsp_data;
    logic [1:0]       dma_sel;      // one-hot: the DMA's request's target, NET or LOCAL
    logic [1:0]       dma_tgt_valid;
    logic [1:0]       dma_tgt_ready;
    logic [1:0]       dma_tgt_rsp_valid;
    line_t            dma_line;     // the DMA's word in every word of a line
    line_strb_t       dma_line_strb;    // its strobes in its own word
    word_t            dma_local_rsp;    // the word of the local memory's answer it read

    // The local memory's ReqMux: 0 the core's data (the scratchpad), 1 the core's memory
    // port's local requests (the I-cache's misses), 2 the DMA's; a request's fields: the
    // line's address in the memory, the line and its strobes.
    localparam LM_FIELDS = MEM_ADDR_WIDTH - LINE_START + $bits(line_t) + $bits(line_strb_t);
    logic [2:0][LM_FIELDS-1:0]            lm_fields;
    wire  [2:0]                           lm_ready;
    wire  [2:0]                           lm_rsp_valid;
    line_t                                local_rsp_data;
    wire                                  ram_valid;
    wire                                  ram_ready;
    wire                                  ram_we;
    /* verilator lint_off UNUSEDSIGNAL */
    wire                                  ram_rsp;    // the memory answers every read
    /* verilator lint_on UNUSEDSIGNAL */
    wire  [LM_FIELDS-1:0]                 ram_fields;
    logic [MEM_ADDR_WIDTH-LINE_START-1:0] ram_line;   // the line's address in the memory
    line_t                                ram_wdata;
    line_strb_t                           ram_wstrb;
    wire                                  ram_rsp_valid;
    line_t                                ram_rsp_data;

    // The network interface's ReqMux: 0 the core's, 1 the DMA's; a request's fields: the
    // byte address, size, atomic operation, CBO, exclusive, the word and its strobes.
    localparam NI_FIELDS = $bits(word_t) + $bits(size_t) + $bits(AtomicPkg::atop_t) +
                           $bits(CachePkg::cmo_t) + 1 + $bits(word_t) + $bits(strb_t);
    logic [1:0][NI_FIELDS-1:0] ni_fields;
    wire  [1:0]                ni_ready;
    wire  [1:0]                ni_rsp_valid;
    wire                       net_valid;
    wire                       net_ready;
    wire                       net_we;
    wire                       net_rsp;
    wire  [NI_FIELDS-1:0]      net_fields;
    word_t                     net_addr;
    size_t                     net_size;
    AtomicPkg::atop_t          net_atop;
    CachePkg::cmo_t            net_cmo;
    logic                      net_excl;
    word_t                     net_wdata;
    strb_t                     net_wstrb;
    wire                       net_if_rsp_valid;    // the network interface's answers
    word_t                     net_if_rsp_data;
    word_t                     net_rsp_data;        // ... to the core and the DMA

    Mig6Core #(.CFG(CFG), .HART_ID(HART_ID), .MY_PE_GRID_X(8'(MY_PE_GRID_X)),
               .MY_PE_GRID_Y(8'(MY_PE_GRID_Y))) u_mig6_core(
        .clk, .rst_n, .mem_req, .mem_rsp, .uncached(1'b0), .meip(1'b0), .lmem_req,
        .lmem_rsp, .halt, .retire, .pipe_trace, .dbg_req, .dbg_rsp);

    // The core's memory port, by its region's target (an access in no region stops the run
    // below; it goes to the local memory meanwhile).
    // @kb: rtl/design/mig6/dma
    assign mem_pma    = Mig6PmaPkg::pma_of(mem_req.addr);
    assign sel[NET]   = mem_pma.hit && mem_pma.target == Mig6PmaPkg::TARGET_NET;
    assign sel[DMA]   = mem_pma.hit && mem_pma.target == Mig6PmaPkg::TARGET_DEVICES;
    assign sel[LOCAL] = !sel[NET] && !sel[DMA];

    ReqDemux #(.N_TARGETS(3), .RSP_WIDTH($bits(line_t))) u_req_demux(
        .clk, .rst_n,
        .req_valid(mem_req.valid), .req_ready(mem_rsp.ready), .req_rsp(mem_req.rsp),
        .req_sel(sel), .rsp_valid(mem_rsp.valid), .rsp_data(mem_rsp.data),
        .tgt_req_valid(tgt_valid), .tgt_req_ready(tgt_ready), .tgt_rsp_valid(tgt_rsp_valid),
        .tgt_rsp_data({{LINE_WORDS{dma_rdata}}, {LINE_WORDS{net_rsp_data}}, local_rsp_data}));

    // The DMA's memory side, by its region's target: the local memory or the network.
    assign dma_pma        = Mig6PmaPkg::pma_of(dma_mem_addr);
    assign dma_sel[NET]   = dma_pma.hit && dma_pma.target == Mig6PmaPkg::TARGET_NET;
    assign dma_sel[LOCAL] = !dma_sel[NET];

    ReqDemux #(.N_TARGETS(2), .RSP_WIDTH($bits(word_t))) u_dma_demux(
        .clk, .rst_n,
        .req_valid(dma_mem_valid), .req_ready(dma_mem_ready), .req_rsp(!dma_mem_we),
        .req_sel(dma_sel), .rsp_valid(dma_mem_rsp_valid), .rsp_data(dma_mem_rsp_data),
        .tgt_req_valid(dma_tgt_valid), .tgt_req_ready(dma_tgt_ready),
        .tgt_rsp_valid(dma_tgt_rsp_valid), .tgt_rsp_data({net_rsp_data, dma_local_rsp}));

    // Words and lines: the core's word of its line (to the network, the DMA's registers);
    // the DMA's word into a line (to the local memory) and out of the local memory's line.
    if (LINE_WORDS == 1) begin: g_one_word
        assign core_wdata    = mem_req.wdata;
        assign core_wstrb    = mem_req.wstrb;
        assign dma_line      = dma_mem_wdata;
        assign dma_line_strb = dma_mem_wstrb;
        assign dma_local_rsp = local_rsp_data;
    end else begin: g_words
        localparam WORD_BITS = LINE_START - DADDR_START;
        word_t [LINE_WORDS-1:0] words;
        strb_t [LINE_WORDS-1:0] strbs;
        word_t [LINE_WORDS-1:0] rsp_words;
        logic  [WORD_BITS-1:0]  dma_word;   // the word of the DMA's local read

        assign words         = mem_req.wdata;
        assign strbs         = mem_req.wstrb;
        assign core_wdata    = words[mem_req.addr[LINE_START-1:DADDR_START]];
        assign core_wstrb    = strbs[mem_req.addr[LINE_START-1:DADDR_START]];
        assign dma_line      = {LINE_WORDS{dma_mem_wdata}};
        assign dma_line_strb = line_strb_t'(dma_mem_wstrb)
                               << (STRB_WIDTH * dma_mem_addr[LINE_START-1:DADDR_START]);

        // The local memory answers in the clock after it takes a read (a_dma_local_next):
        // the index kept at that edge belongs to the answer coming.
        always_ff @(posedge clk)
            if (dma_tgt_valid[LOCAL] && dma_tgt_ready[LOCAL])
                dma_word <= dma_mem_addr[LINE_START-1:DADDR_START];

        assign rsp_words     = local_rsp_data;
        assign dma_local_rsp = rsp_words[dma_word];
    end

    // The local memory's requesters: the core's data first (it is always ready, so a data
    // request is taken in the clock it comes), the I-cache's misses, the DMA.
    // @kb: rtl/design/mig6/scratchpad
    assign lm_fields[0] = {lmem_req.addr[MEM_ADDR_WIDTH-1:LINE_START], lmem_req.wdata,
                           lmem_req.wstrb};
    assign lm_fields[1] = {mem_req.addr[MEM_ADDR_WIDTH-1:LINE_START], mem_req.wdata,
                           mem_req.wstrb};
    assign lm_fields[2] = {dma_mem_addr[MEM_ADDR_WIDTH-1:LINE_START], dma_line, dma_line_strb};
    ReqMux #(.N_REQ(3), .REQ_WIDTH(LM_FIELDS), .RSP_WIDTH($bits(line_t)), .PENDING_WIDTH(1),
             .FIXED_PRIO(1)) u_local_mux(
        .clk, .rst_n,
        .req_valid({dma_tgt_valid[LOCAL], tgt_valid[LOCAL], lmem_req.valid}),
        .req_ready(lm_ready),
        .req_we({dma_mem_we, mem_req.we, lmem_req.we}),
        .req_rsp({!dma_mem_we, mem_req.rsp, lmem_req.rsp}),
        .req_fields(lm_fields), .rsp_valid(lm_rsp_valid), .rsp_data(local_rsp_data),
        .tgt_req_valid(ram_valid), .tgt_req_ready(ram_ready), .tgt_req_we(ram_we),
        .tgt_req_rsp(ram_rsp), .tgt_req_fields(ram_fields),
        .tgt_rsp_valid(ram_rsp_valid), .tgt_rsp_data(ram_rsp_data));
    assign {ram_line, ram_wdata, ram_wstrb} = ram_fields;
    assign lmem_rsp.ready           = lm_ready[0];
    assign lmem_rsp.valid           = lm_rsp_valid[0];
    assign lmem_rsp.data            = local_rsp_data;
    assign tgt_ready[LOCAL]         = lm_ready[1];
    assign tgt_rsp_valid[LOCAL]     = lm_rsp_valid[1];
    assign dma_tgt_ready[LOCAL]     = lm_ready[2];
    assign dma_tgt_rsp_valid[LOCAL] = lm_rsp_valid[2];

    // The local memory, code and data; latency 1, always ready.
    SimLatencyRAM #(.DATA_SIZE(LINE_SIZE), .ADDR_WIDTH(MEM_ADDR_WIDTH),
                    .READY_PERCENT(100), .FAST_PERCENT(100), .FAST_MIN(1), .FAST_MAX(1),
                    .MAX_PENDING(1)) u_local_mem(
        .clk, .rst_n,
        .req_valid(ram_valid), .req_ready(ram_ready), .req_we(ram_we),
        .req_addr({ram_line, {LINE_START{1'b0}}}), .req_wdata(ram_wdata),
        .req_wstrb(ram_wstrb), .rsp_valid(ram_rsp_valid), .rsp_data(ram_rsp_data));

    // The network interface's requesters, round-robin: the core's, the DMA's.
    assign ni_fields[0] = {mem_req.addr, mem_req.size, mem_req.atop, mem_req.cmo, mem_req.excl,
                           core_wdata, core_wstrb};
    assign ni_fields[1] = {dma_mem_addr, dma_mem_size, AtomicPkg::ATOP_NONE,
                           CachePkg::CMO_NONE, 1'b0, dma_mem_wdata, dma_mem_wstrb};
    ReqMux #(.N_REQ(2), .REQ_WIDTH(NI_FIELDS), .RSP_WIDTH($bits(word_t)), .PENDING_WIDTH(2))
        u_net_mux(
            .clk, .rst_n,
            .req_valid({dma_tgt_valid[NET], tgt_valid[NET]}), .req_ready(ni_ready),
            .req_we({dma_mem_we, mem_req.we}), .req_rsp({!dma_mem_we, mem_req.rsp}),
            .req_fields(ni_fields), .rsp_valid(ni_rsp_valid), .rsp_data(net_rsp_data),
            .tgt_req_valid(net_valid), .tgt_req_ready(net_ready), .tgt_req_we(net_we),
            .tgt_req_rsp(net_rsp), .tgt_req_fields(net_fields),
            .tgt_rsp_valid(net_if_rsp_valid), .tgt_rsp_data(net_if_rsp_data));
    assign {net_addr, net_size, net_atop, net_cmo, net_excl, net_wdata, net_wstrb} = net_fields;
    assign tgt_ready[NET]         = ni_ready[0];
    assign tgt_rsp_valid[NET]     = ni_rsp_valid[0];
    assign dma_tgt_ready[NET]     = ni_ready[1];
    assign dma_tgt_rsp_valid[NET] = ni_rsp_valid[1];

    Mig6PeNetIf #(.MY_PE_GRID_X(MY_PE_GRID_X), .MY_PE_GRID_Y(MY_PE_GRID_Y),
                  .BUF_DEPTH(NOC_BUF_DEPTH)) u_net_if(
        .clk, .rst_n,
        .req_valid(net_valid), .req_ready(net_ready), .req_we(net_we),
        .req_addr(net_addr), .req_size(net_size), .req_atop(net_atop),
        .req_cmo(net_cmo), .req_excl(net_excl), .req_rsp(net_rsp),
        .req_wdata(net_wdata), .req_wstrb(net_wstrb),
        .rsp_valid(net_if_rsp_valid), .rsp_data(net_if_rsp_data),
        .noc_req_fwd, .noc_req_bwd, .noc_rsp_fwd, .noc_rsp_bwd);

    // The DMA: its registers on the core's memory port (the region dma), its memory side to
    // the crossbar; polled.
    DmaSifive #(.N_CHANNELS(DMA_N), .ADDR_WIDTH($bits(word_t)), .DATA_WIDTH($bits(word_t)),
                .LEN_WIDTH($bits(word_t))) u_dma(
        .clk, .rst_n,
        .req_valid(tgt_valid[DMA]), .req_ready(dma_reg_ready), .req_we(mem_req.we),
        .req_addr(mem_req.addr[DMA_ADDR_WIDTH-1:0]), .req_wdata(core_wdata),
        .req_wstrb(core_wstrb), .rsp_valid(tgt_rsp_valid[DMA]), .rsp_rdata(dma_rdata),
        .mem_req_valid(dma_mem_valid), .mem_req_ready(dma_mem_ready), .mem_req_we(dma_mem_we),
        .mem_req_addr(dma_mem_addr), .mem_req_size(dma_mem_size),
        .mem_req_wdata(dma_mem_wdata), .mem_req_wstrb(dma_mem_wstrb),
        .mem_rsp_valid(dma_mem_rsp_valid), .mem_rsp_data(dma_mem_rsp_data), .irq(dma_irq));
    assign tgt_ready[DMA] = dma_reg_ready;

    // The memory map: every access in a region; AMOs only where the region has atomics (the
    // shared memory's AtomicUnit; none in front of the local memory or the DMA).
    `DC_ASSERT(a_in_region, !(mem_req.valid && !mem_pma.hit))
    `DC_ASSERT(a_atomics_allowed,
               !(mem_req.valid && AtomicPkg::is_atomic(mem_req.atop) && !mem_pma.atomics))
    // An exclusive LR or SC goes to the network interface: the shared memory's monitor.
    `DC_ASSERT(a_excl_to_net, !(mem_req.valid && mem_req.excl && !sel[NET]))
    // The scratchpad: plain loads and stores (a CBO writes no byte).
    `DC_ASSERT(a_lmem_plain,
               !(lmem_req.valid && (AtomicPkg::is_atomic(lmem_req.atop) || lmem_req.excl)))
    // The DMA moves between the local memory and the network only.
    `DC_ASSERT(a_dma_target, !(dma_mem_valid && !(dma_pma.hit &&
                               (dma_pma.target == Mig6PmaPkg::TARGET_LOCAL ||
                                dma_pma.target == Mig6PmaPkg::TARGET_NET))))
    // The DMA's local read is answered in the clock after the memory takes it: the word
    // index kept then is its answer's.
    `DC_ASSERT_NEXT(a_dma_local_next,
                    dma_tgt_valid[LOCAL] && dma_tgt_ready[LOCAL] && !dma_mem_we,
                    dma_tgt_rsp_valid[LOCAL])

    // Load the hex image into the local memory, returns 1 when it is loaded.
    function automatic int load(string hex);
        return u_local_mem.load(hex, u_local_mem.VLOG_HEX_FORMAT);
    endfunction

    // Byte at address a of the local memory (its offset in the region).
    function automatic logic [7:0] peek(input logic [MEM_ADDR_WIDTH-1:0] a);
        return u_local_mem.peek(a);
    endfunction

endmodule

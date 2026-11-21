/* Mig6 PE (processing element), for simulation: one Mig6Core, its local memory, its DMA, its
 * PLIC and its network interface.
 *
 * A prototype (rtl/design/mig6/README.md). The local memory is the code and data of the
 * program, private to the PE: a SimLatencyRAM (latency 1, always ready). It is a scratchpad
 * for data (kb rtl/design/mig6/scratchpad): the core's loads and stores to it come on the
 * core's data port (lmem), past the D-cache, answered in the clock after as a hit is.
 *
 * Three requesters, the core's memory port (the I-cache's misses, the D-cache's requests:
 * far ones and the DMA's registers), the DMA's read channel and the DMA's write channel,
 * reach two targets, the local memory and the network interface, through a crossbar of the
 * library's channels (kb rtl/design/mig6/dma, dma_depth): a ReqDemux for each requester, by
 * its address's region (Mig6PmaPkg, cfg/mig6_pma.yaml: target local, net or devices), and a
 * ReqMux in front of each target. So the core works on the local memory while the DMA waits
 * for the network, and the DMA's writes never wait for the answers its reads are owed (a
 * ReqDemux holds a switch of target while answers are owed; the write channel's owes none).
 * The local memory's ReqMux is by fixed priority, the core's data first (taken in the clock
 * it comes: Mig6Caches a_lmem_taken; kb rtl/lib/block/req_mux/fixed_priority), then the
 * I-cache's misses, the DMA's writes (they drain what its reads brought), its reads; the
 * network interface's is round-robin, the core's requests and the DMA's reads and writes.
 * The core's stores to the shared memory are in the network before a later DMA read of
 * them: both pass the one network interface, in order.
 *
 * The DMA is the library's DmaSifiveSplit (SiFive's PDMA map, sw/riscv/drivers/dma.h), its
 * registers the region dma (target devices), one DMA channel per 4 KiB of it, up to
 * CFG.dma_depth transactions in flight (kb rtl/lib/block/dma/pipelined_mover,
 * issue_pointer), its writes unanswered (WR_ACK 0: the local memory writes in the clock it
 * takes a write, and nothing in Mig6 answers a plain write yet). Its done and error
 * are sources of the PE's PLIC (the library's Plic, sw/riscv/drivers/plic.h; kb
 * rtl/design/mig6/plic): channel c's at CFG.dma_source + 2c and + 2c + 1, level-triggered;
 * its one context is the core's meip, the machine external interrupt. The PLIC's registers
 * are the region plic; AddrDecode tells the two devices apart by their regions. The DMA's
 * channels carry a word (the network interface's): a word written to the local memory goes
 * into every word of the line, its strobes in its own; a word read from it is picked from
 * the line by the word index kept when the read was taken, right while the local memory
 * answers in the clock after (a_dma_local_next), however many reads the DMA keeps in
 * flight. The network interface takes a word: the core's word is the one of its
 * line the address names, and the answer goes into every word of the line, as for the
 * DMA's registers.
 *
 * LR/SC on the local memory are decided at its port, where every request to it passes (the
 * core's data, the I-cache's misses, the DMA's), by an exclusive monitor (the library's
 * ExclusiveMonitor, u_local_monitor; kb rtl/design/mig6/local_lr_sc), as the shared
 * memory's are at its network interface: an LR (an exclusive read, the core's data port
 * only) reserves its line; every write the memory takes ends the reservation of its line,
 * the DMA's and the core's own (interrupt handlers' too); an SC (an exclusive write) is
 * decided when the memory would take it: with the reservation it writes, without it goes
 * nowhere; either way it ends the reservation and its status (RISC-V's SC result: 0 stored,
 * 1 failed) is answered in the clock after, where a read's answer comes (the memory answers
 * reads only, a_sc_alone). A reservation is a line, the memory's request (the spec allows a
 * set larger than the word: a store to the line's other word ends it too).
 *
 * Checked by assertions, with the regions' attributes: every access is in a region
 * (a_in_region; later an access fault); no AMO goes to a region without atomics
 * (a_atomics_allowed); the scratchpad gets no AMO (a_lmem_no_amo: no AtomicUnit in front of
 * the local memory); an exclusive request on the memory port goes to the network
 * (a_excl_to_net; local ones come on lmem); the DMA reads and writes only the local memory
 * and the network (a_dma_rd_target, a_dma_wr_target).
 *
 *   Mig6Core --lmem (data, local)-----------------------------> u_local_mux 0 --+
 *            --mem--> u_req_demux --local---------------------> u_local_mux 1   |
 *                                 --net ---> u_net_mux 0 --+                   |
 *                                 --u_dma's, u_plic's regs |                   |
 *   u_dma write --> u_dma_wr_demux --local -------------------> u_local_mux 2   |
 *                                  --net ---> u_net_mux 2 --+                   |
 *   u_dma read  --> u_dma_rd_demux --local -------------------> u_local_mux 3 --+
 *                                  --net ---> u_net_mux 1 --+           u_local_mem
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
    // The PLIC: the DMA's sources from CFG.dma_source, two a channel.
    localparam PLIC_ADDR_WIDTH = Mig6PmaPkg::PLIC_ADDR_WIDTH;
    localparam N_SOURCES       = CFG.dma_source + 2 * DMA_N - 1;
    localparam DMA_DEPTH = CFG.dma_depth;   // the DMA's transactions in flight
    localparam DMA_PW    = (DMA_DEPTH > 1) ? $clog2(DMA_DEPTH) : 1;    // its reads' answers
    localparam LOCAL = 0;           // the requesters' targets
    localparam NET   = 1;
    localparam DMA   = 2;           // ... the core's only: the DMA's registers
    localparam PLIC  = 3;           // ... and the PLIC's

    // Programs are linked to start at the local memory's base (sw/riscv/mig6/mig6.ld).
    `DC_STATIC_ASSERT(a_reset_in_local, CFG.rst_addr == Mig6PmaPkg::LOCAL_BASE)
    `DC_STATIC_ASSERT(a_dma_channels, DMA_ADDR_WIDTH >= DmaSifivePkg::CHAN_BITS)
    `DC_STATIC_ASSERT(a_plic_sources, CFG.dma_source >= 1 && CFG.plic_prio_width >= 1)
    `DC_STATIC_ASSERT(a_dma_depth, DMA_DEPTH >= 1 && (1 << DMA_PW) >= DMA_DEPTH)

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
    Mig6PmaPkg::pma_t rd_pma;       // the DMA's read's region
    Mig6PmaPkg::pma_t wr_pma;       // the DMA's write's region
    /* verilator lint_on UNUSEDSIGNAL */
    logic [3:0]       sel;          // one-hot: the core's request's target
    wire              sel_dma;      // ... the DMA's registers
    wire              sel_plic;     // ... the PLIC's
    /* verilator lint_off UNUSEDSIGNAL */
    wire              dev_miss;     // in neither device (the memory map's region tells)
    /* verilator lint_on UNUSEDSIGNAL */
    logic [3:0]       tgt_valid;
    logic [3:0]       tgt_ready;
    logic [3:0]       tgt_rsp_valid;
    word_t            core_wdata;   // the word of the core's line the address names
    strb_t            core_wstrb;

    // The DMA and the PLIC.
    wire              dma_reg_ready;
    word_t            dma_rdata;
    wire [2*DMA_N-1:0] dma_irq;     // 2c channel c's done, 2c + 1 its error
    wire              plic_ready;
    word_t            plic_rdata;
    wire [N_SOURCES:1] plic_src;    // the PLIC's sources
    wire              meip;         // its context 0: the core's machine external interrupt
    // The DMA's read channel (source beats, answered in order) and write channel (posted).
    wire              rd_valid;
    wire              rd_ready;
    word_t            rd_addr;
    size_t            rd_size;
    wire              rd_rsp_valid;
    word_t            rd_rsp_data;
    wire              wr_valid;
    wire              wr_ready;
    word_t            wr_addr;
    size_t            wr_size;
    word_t            wr_wdata;
    strb_t            wr_wstrb;
    // The write channel wants no answer (WR_ACK 0), so its demux returns none.
    /* verilator lint_off UNUSEDSIGNAL */
    wire              wr_rsp;
    wire              wr_rsp_valid;
    word_t            wr_rsp_data;
    /* verilator lint_on UNUSEDSIGNAL */
    logic [1:0]       rd_sel;       // one-hot: the DMA read's target, NET or LOCAL
    logic [1:0]       rd_tgt_valid;
    logic [1:0]       rd_tgt_ready;
    logic [1:0]       rd_tgt_rsp_valid;
    logic [1:0]       wr_sel;       // ... the DMA write's
    logic [1:0]       wr_tgt_valid;
    logic [1:0]       wr_tgt_ready;
    line_t            dma_line;     // the DMA's word in every word of a line
    line_strb_t       dma_line_strb;    // its strobes in its own word
    word_t            dma_local_rsp;    // the word of the local memory's answer it read

    // The local memory's ReqMux: 0 the core's data (the scratchpad), 1 the core's memory
    // port's local requests (the I-cache's misses), 2 the DMA's writes, 3 its reads; a
    // request's fields: the line's address in the memory, the line, its strobes, exclusive
    // (LR, SC).
    localparam LM_FIELDS = MEM_ADDR_WIDTH - LINE_START + $bits(line_t) + $bits(line_strb_t)
                           + 1;
    logic [3:0][LM_FIELDS-1:0]            lm_fields;
    wire  [3:0]                           lm_ready;
    wire  [3:0]                           lm_rsp_valid;
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
    logic                                 ram_excl;
    wire                                  ram_rsp_valid;  // to the ReqMux: the memory's
    line_t                                ram_rsp_data;   //   answers and the SCs' status
    // The local memory's exclusive monitor.
    wire                                  ram_take;   // a request taken: the memory is ready
    wire                                  ram_lr;     // ... an LR
    wire                                  ram_sc;     // ... an SC
    wire                                  sc_ok;      // its reservation holds: it writes
    logic                                 sc_rsp_valid;   // an SC's status, the clock after
    logic                                 sc_failed;
    wire                                  mem_valid;  // the memory's request: a failing SC
                                                      // goes nowhere
    wire                                  mem_rsp_valid;  // the memory's answers: reads
    line_t                                mem_rsp_data;

    // The network interface's ReqMux: 0 the core's, 1 the DMA's reads, 2 its writes; a
    // request's fields: the byte address, size, atomic operation, CBO, exclusive, the word
    // and its strobes.
    localparam NI_FIELDS = $bits(word_t) + $bits(size_t) + $bits(AtomicPkg::atop_t) +
                           $bits(CachePkg::cmo_t) + 1 + $bits(word_t) + $bits(strb_t);
    logic [2:0][NI_FIELDS-1:0] ni_fields;
    wire  [2:0]                ni_ready;
    wire  [2:0]                ni_rsp_valid;
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
        .clk, .rst_n, .mem_req, .mem_rsp, .uncached(1'b0), .meip, .lmem_req,
        .lmem_rsp, .halt, .retire, .pipe_trace, .dbg_req, .dbg_rsp);

    // The core's memory port, by its region's target (an access in no region stops the run
    // below; it goes to the local memory meanwhile).
    // @kb: rtl/design/mig6/dma
    assign mem_pma    = Mig6PmaPkg::pma_of(mem_req.addr);
    assign sel[NET]   = mem_pma.hit && mem_pma.target == Mig6PmaPkg::TARGET_NET;
    assign sel[DMA]   = sel_dma;
    assign sel[PLIC]  = sel_plic;
    assign sel[LOCAL] = !sel[NET] && !sel_dma && !sel_plic;

    // The devices, by their regions: rule 0 the PLIC, rule 1 the DMA.
    // @kb: rtl/design/mig6/plic
    AddrDecode #(.ADDR_WIDTH($bits(word_t)), .N_RULES(2),
                 .BASES({Mig6PmaPkg::DMA_BASE, Mig6PmaPkg::PLIC_BASE}),
                 .WIDTHS({8'(DMA_ADDR_WIDTH), 8'(PLIC_ADDR_WIDTH)}))
        u_addr_decode(.addr(mem_req.addr), .sel({sel_dma, sel_plic}), .miss(dev_miss));

    ReqDemux #(.N_TARGETS(4), .RSP_WIDTH($bits(line_t))) u_req_demux(
        .clk, .rst_n,
        .req_valid(mem_req.valid), .req_ready(mem_rsp.ready), .req_rsp(mem_req.rsp),
        .req_sel(sel), .rsp_valid(mem_rsp.valid), .rsp_data(mem_rsp.data),
        .tgt_req_valid(tgt_valid), .tgt_req_ready(tgt_ready), .tgt_rsp_valid(tgt_rsp_valid),
        .tgt_rsp_data({{LINE_WORDS{plic_rdata}}, {LINE_WORDS{dma_rdata}},
                       {LINE_WORDS{net_rsp_data}}, local_rsp_data}));

    // The DMA's reads and writes, each by its region's target: the local memory or the
    // network. The reads' demux keeps DMA_DEPTH answers in order; the writes' owes none, so
    // it never holds a switch of target.
    // @kb: rtl/design/mig6/dma_depth
    assign rd_pma        = Mig6PmaPkg::pma_of(rd_addr);
    assign rd_sel[NET]   = rd_pma.hit && rd_pma.target == Mig6PmaPkg::TARGET_NET;
    assign rd_sel[LOCAL] = !rd_sel[NET];
    assign wr_pma        = Mig6PmaPkg::pma_of(wr_addr);
    assign wr_sel[NET]   = wr_pma.hit && wr_pma.target == Mig6PmaPkg::TARGET_NET;
    assign wr_sel[LOCAL] = !wr_sel[NET];

    ReqDemux #(.N_TARGETS(2), .RSP_WIDTH($bits(word_t)), .PENDING_WIDTH(DMA_PW))
        u_dma_rd_demux(
            .clk, .rst_n,
            .req_valid(rd_valid), .req_ready(rd_ready), .req_rsp(1'b1),
            .req_sel(rd_sel), .rsp_valid(rd_rsp_valid), .rsp_data(rd_rsp_data),
            .tgt_req_valid(rd_tgt_valid), .tgt_req_ready(rd_tgt_ready),
            .tgt_rsp_valid(rd_tgt_rsp_valid), .tgt_rsp_data({net_rsp_data, dma_local_rsp}));
    ReqDemux #(.N_TARGETS(2), .RSP_WIDTH($bits(word_t))) u_dma_wr_demux(
        .clk, .rst_n,
        .req_valid(wr_valid), .req_ready(wr_ready), .req_rsp(1'b0),
        .req_sel(wr_sel), .rsp_valid(wr_rsp_valid), .rsp_data(wr_rsp_data),
        .tgt_req_valid(wr_tgt_valid), .tgt_req_ready(wr_tgt_ready),
        .tgt_rsp_valid(2'b00), .tgt_rsp_data({2{word_t'(0)}}));

    // Words and lines: the core's word of its line (to the network, the DMA's registers);
    // the DMA's word into a line (to the local memory) and out of the local memory's line.
    if (LINE_WORDS == 1) begin: g_one_word
        assign core_wdata    = mem_req.wdata;
        assign core_wstrb    = mem_req.wstrb;
        assign dma_line      = wr_wdata;
        assign dma_line_strb = wr_wstrb;
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
        assign dma_line      = {LINE_WORDS{wr_wdata}};
        assign dma_line_strb = line_strb_t'(wr_wstrb)
                               << (STRB_WIDTH * wr_addr[LINE_START-1:DADDR_START]);

        // The local memory answers in the clock after it takes a read (a_dma_local_next):
        // the index kept at that edge belongs to the answer coming.
        always_ff @(posedge clk)
            if (rd_tgt_valid[LOCAL] && rd_tgt_ready[LOCAL])
                dma_word <= rd_addr[LINE_START-1:DADDR_START];

        assign rsp_words     = local_rsp_data;
        assign dma_local_rsp = rsp_words[dma_word];
    end

    // The local memory's requesters: the core's data first (it is always ready, so a data
    // request is taken in the clock it comes), the I-cache's misses, the DMA's writes, its
    // reads.
    // @kb: rtl/design/mig6/scratchpad
    assign lm_fields[0] = {lmem_req.addr[MEM_ADDR_WIDTH-1:LINE_START], lmem_req.wdata,
                           lmem_req.wstrb, lmem_req.excl};
    assign lm_fields[1] = {mem_req.addr[MEM_ADDR_WIDTH-1:LINE_START], mem_req.wdata,
                           mem_req.wstrb, 1'b0};
    assign lm_fields[2] = {wr_addr[MEM_ADDR_WIDTH-1:LINE_START], dma_line, dma_line_strb, 1'b0};
    assign lm_fields[3] = {rd_addr[MEM_ADDR_WIDTH-1:LINE_START], {$bits(line_t){1'b0}},
                           {$bits(line_strb_t){1'b0}}, 1'b0};
    ReqMux #(.N_REQ(4), .REQ_WIDTH(LM_FIELDS), .RSP_WIDTH($bits(line_t)), .PENDING_WIDTH(1),
             .FIXED_PRIO(1)) u_local_mux(
        .clk, .rst_n,
        .req_valid({rd_tgt_valid[LOCAL], wr_tgt_valid[LOCAL], tgt_valid[LOCAL], lmem_req.valid}),
        .req_ready(lm_ready),
        .req_we({1'b0, 1'b1, mem_req.we, lmem_req.we}),
        .req_rsp({1'b1, 1'b0, mem_req.rsp, lmem_req.rsp}),
        .req_fields(lm_fields), .rsp_valid(lm_rsp_valid), .rsp_data(local_rsp_data),
        .tgt_req_valid(ram_valid), .tgt_req_ready(ram_ready), .tgt_req_we(ram_we),
        .tgt_req_rsp(ram_rsp), .tgt_req_fields(ram_fields),
        .tgt_rsp_valid(ram_rsp_valid), .tgt_rsp_data(ram_rsp_data));
    assign {ram_line, ram_wdata, ram_wstrb, ram_excl} = ram_fields;
    assign lmem_rsp.ready           = lm_ready[0];
    assign lmem_rsp.valid           = lm_rsp_valid[0];
    assign lmem_rsp.data            = local_rsp_data;
    assign tgt_ready[LOCAL]         = lm_ready[1];
    assign tgt_rsp_valid[LOCAL]     = lm_rsp_valid[1];
    assign wr_tgt_ready[LOCAL]      = lm_ready[2];
    assign rd_tgt_ready[LOCAL]      = lm_ready[3];
    assign rd_tgt_rsp_valid[LOCAL]  = lm_rsp_valid[3];

    // LR/SC on the local memory: every request to it passes here, in the order the memory
    // takes them. An LR reserves its line, every write the memory takes ends the
    // reservation of its line, an SC writes only with its reservation and is answered with
    // its status in the clock after (the memory answers reads only).
    // @kb: rtl/design/mig6/local_lr_sc
    assign ram_take = ram_valid && ram_ready;
    assign ram_lr   = ram_take && ram_excl && !ram_we;
    assign ram_sc   = ram_take && ram_excl && ram_we;

    ExclusiveMonitor #(.N_AGENTS(1), .ADDR_WIDTH(MEM_ADDR_WIDTH), .RESV_OFFSET(LINE_START))
        u_local_monitor(
            .clk, .rst_n,
            .reserve(ram_lr), .reserve_agent(1'b0), .reserve_addr({ram_line, {LINE_START{1'b0}}}),
            .write(ram_take && ram_we && (!ram_excl || sc_ok)),
            .write_addr({ram_line, {LINE_START{1'b0}}}),
            .sc_agent(1'b0), .sc_addr({ram_line, {LINE_START{1'b0}}}), .sc_ok,
            .sc_done(ram_sc));

    always_ff @(posedge clk)
        if (!rst_n)
            sc_rsp_valid <= 1'b0;
        else
            sc_rsp_valid <= ram_sc;

    always_ff @(posedge clk)
        if (ram_sc)
            sc_failed <= !sc_ok;

    assign mem_valid     = ram_valid && !(ram_excl && ram_we && !sc_ok);
    assign ram_rsp_valid = mem_rsp_valid || sc_rsp_valid;
    assign ram_rsp_data  = sc_rsp_valid ? {LINE_WORDS{word_t'(sc_failed)}} : mem_rsp_data;

    // The local memory, code and data; latency 1, always ready.
    SimLatencyRAM #(.DATA_SIZE(LINE_SIZE), .ADDR_WIDTH(MEM_ADDR_WIDTH),
                    .READY_PERCENT(100), .FAST_PERCENT(100), .FAST_MIN(1), .FAST_MAX(1),
                    .MAX_PENDING(1)) u_local_mem(
        .clk, .rst_n,
        .req_valid(mem_valid), .req_ready(ram_ready), .req_we(ram_we),
        .req_addr({ram_line, {LINE_START{1'b0}}}), .req_wdata(ram_wdata),
        .req_wstrb(ram_wstrb), .rsp_valid(mem_rsp_valid), .rsp_data(mem_rsp_data));

    // The network interface's requesters, round-robin: the core's, the DMA's reads, its
    // writes; room for the DMA's reads' answers and the core's.
    assign ni_fields[0] = {mem_req.addr, mem_req.size, mem_req.atop, mem_req.cmo, mem_req.excl,
                           core_wdata, core_wstrb};
    assign ni_fields[1] = {rd_addr, rd_size, AtomicPkg::ATOP_NONE, CachePkg::CMO_NONE, 1'b0,
                           word_t'(0), strb_t'(0)};
    assign ni_fields[2] = {wr_addr, wr_size, AtomicPkg::ATOP_NONE, CachePkg::CMO_NONE, 1'b0,
                           wr_wdata, wr_wstrb};
    ReqMux #(.N_REQ(3), .REQ_WIDTH(NI_FIELDS), .RSP_WIDTH($bits(word_t)),
             .PENDING_WIDTH(DMA_PW + 1)) u_net_mux(
            .clk, .rst_n,
            .req_valid({wr_tgt_valid[NET], rd_tgt_valid[NET], tgt_valid[NET]}),
            .req_ready(ni_ready),
            .req_we({1'b1, 1'b0, mem_req.we}), .req_rsp({1'b0, 1'b1, mem_req.rsp}),
            .req_fields(ni_fields), .rsp_valid(ni_rsp_valid), .rsp_data(net_rsp_data),
            .tgt_req_valid(net_valid), .tgt_req_ready(net_ready), .tgt_req_we(net_we),
            .tgt_req_rsp(net_rsp), .tgt_req_fields(net_fields),
            .tgt_rsp_valid(net_if_rsp_valid), .tgt_rsp_data(net_if_rsp_data));
    assign {net_addr, net_size, net_atop, net_cmo, net_excl, net_wdata, net_wstrb} = net_fields;
    assign tgt_ready[NET]         = ni_ready[0];
    assign tgt_rsp_valid[NET]     = ni_rsp_valid[0];
    assign rd_tgt_ready[NET]      = ni_ready[1];
    assign rd_tgt_rsp_valid[NET]  = ni_rsp_valid[1];
    assign wr_tgt_ready[NET]      = ni_ready[2];

    Mig6PeNetIf #(.MY_PE_GRID_X(MY_PE_GRID_X), .MY_PE_GRID_Y(MY_PE_GRID_Y),
                  .BUF_DEPTH(NOC_BUF_DEPTH)) u_net_if(
        .clk, .rst_n,
        .req_valid(net_valid), .req_ready(net_ready), .req_we(net_we),
        .req_addr(net_addr), .req_size(net_size), .req_atop(net_atop),
        .req_cmo(net_cmo), .req_excl(net_excl), .req_rsp(net_rsp),
        .req_wdata(net_wdata), .req_wstrb(net_wstrb),
        .rsp_valid(net_if_rsp_valid), .rsp_data(net_if_rsp_data),
        .noc_req_fwd, .noc_req_bwd, .noc_rsp_fwd, .noc_rsp_bwd);

    // The DMA: its registers on the core's memory port (the region dma), its read and write
    // channels to the crossbar, its done and error to the PLIC.
    DmaSifiveSplit #(.N_CHANNELS(DMA_N), .ADDR_WIDTH($bits(word_t)),
                     .DATA_WIDTH($bits(word_t)), .LEN_WIDTH($bits(word_t)), .DEPTH(DMA_DEPTH),
                     .WR_ACK(0)) u_dma(
        .clk, .rst_n,
        .req_valid(tgt_valid[DMA]), .req_ready(dma_reg_ready), .req_we(mem_req.we),
        .req_addr(mem_req.addr[DMA_ADDR_WIDTH-1:0]), .req_wdata(core_wdata),
        .req_wstrb(core_wstrb), .rsp_valid(tgt_rsp_valid[DMA]), .rsp_rdata(dma_rdata),
        .rd_req_valid(rd_valid), .rd_req_ready(rd_ready), .rd_req_addr(rd_addr),
        .rd_req_size(rd_size), .rd_rsp_valid, .rd_rsp_data,
        .wr_req_valid(wr_valid), .wr_req_ready(wr_ready), .wr_req_addr(wr_addr),
        .wr_req_size(wr_size), .wr_req_wdata(wr_wdata), .wr_req_wstrb(wr_wstrb),
        .wr_req_rsp(wr_rsp), .wr_rsp_valid(1'b0), .irq(dma_irq));
    assign tgt_ready[DMA] = dma_reg_ready;

    // The PLIC: the DMA's done and error from CFG.dma_source, the others 0; one context, the
    // core's meip.
    for (genvar k = 1; k <= N_SOURCES; k++) begin: g_src
        if (k >= CFG.dma_source) begin: g_dma
            assign plic_src[k] = dma_irq[k - CFG.dma_source];
        end else begin: g_none
            assign plic_src[k] = 1'b0;
        end
    end

    Plic #(.N_SOURCES(N_SOURCES), .N_CONTEXTS(1), .PRIO_WIDTH(CFG.plic_prio_width),
           .ADDR_WIDTH(PLIC_ADDR_WIDTH)) u_plic(
        .clk, .rst_n, .src(plic_src), .eip(meip),
        .req_valid(tgt_valid[PLIC]), .req_ready(plic_ready), .req_we(mem_req.we),
        .req_addr(mem_req.addr[PLIC_ADDR_WIDTH-1:0]), .req_wdata(core_wdata),
        .req_wstrb(core_wstrb), .rsp_valid(tgt_rsp_valid[PLIC]), .rsp_rdata(plic_rdata));
    assign tgt_ready[PLIC] = plic_ready;

    // The memory map: every access in a region; AMOs only where the region has atomics (the
    // shared memory's AtomicUnit; none in front of the local memory or the DMA).
    `DC_ASSERT(a_in_region, !(mem_req.valid && !mem_pma.hit))
    `DC_ASSERT(a_atomics_allowed,
               !(mem_req.valid && AtomicPkg::is_atomic(mem_req.atop) && !mem_pma.atomics))
    // An exclusive LR or SC goes to the network interface: the shared memory's monitor.
    `DC_ASSERT(a_excl_to_net, !(mem_req.valid && mem_req.excl && !sel[NET]))
    // The scratchpad: no AMO (a CBO writes no byte; LR and SC are its monitor's).
    `DC_ASSERT(a_lmem_no_amo, !(lmem_req.valid && AtomicPkg::is_atomic(lmem_req.atop)))
    // An SC's status and a read's answer never meet: one request a clock, each answered in
    // the clock after it.
    `DC_ASSERT(a_sc_alone, !(mem_rsp_valid && sc_rsp_valid))
    // The DMA reads and writes the local memory and the network only.
    `DC_ASSERT(a_dma_rd_target, !(rd_valid && !(rd_pma.hit &&
                                  (rd_pma.target == Mig6PmaPkg::TARGET_LOCAL ||
                                   rd_pma.target == Mig6PmaPkg::TARGET_NET))))
    `DC_ASSERT(a_dma_wr_target, !(wr_valid && !(wr_pma.hit &&
                                  (wr_pma.target == Mig6PmaPkg::TARGET_LOCAL ||
                                   wr_pma.target == Mig6PmaPkg::TARGET_NET))))
    // The DMA's writes are posted: no target answers them.
    `DC_ASSERT(a_dma_writes_posted, !lm_rsp_valid[2] && !ni_rsp_valid[2])
    // The DMA's local read is answered in the clock after the memory takes it: the word
    // index kept then is its answer's.
    `DC_ASSERT_NEXT(a_dma_local_next, rd_tgt_valid[LOCAL] && rd_tgt_ready[LOCAL],
                    rd_tgt_rsp_valid[LOCAL])

    // Load the hex image into the local memory, returns 1 when it is loaded.
    function automatic int load(string hex);
        return u_local_mem.load(hex, u_local_mem.VLOG_HEX_FORMAT);
    endfunction

    // Byte at address a of the local memory (its offset in the region).
    function automatic logic [7:0] peek(input logic [MEM_ADDR_WIDTH-1:0] a);
        return u_local_mem.peek(a);
    endfunction

endmodule

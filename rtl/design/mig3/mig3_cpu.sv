/* Mig3 RISC-V CPU for simulation: Mig3Core with its memory, its PLIC, its Timer and its UART.
 *
 * load() puts the hex image (objcopy -O verilog, see sw/riscv/mig3.ld) into the memory, one
 * SimLatencyRAM behind the memory port of the core (code and data: the caches inside the
 * core share it), a cache line (LINE_SIZE bytes) a request, with latency 1 and always ready
 * unless the testbench configures it (configure()). uncached=1 makes the core bypass its
 * caches. It has 1 << CFG.mem_addr_width
 * bytes; the core address bits above them are ignored, so addresses wrap around.
 * The PLIC (rtl/lib/block/plic) is in the I/O region at CFG.io_base + CFG.plic.offset, a
 * region of 1 << CFG.plic.addr_width bytes, the Timer (rtl/lib/block/timer: mtime and the
 * hart's mtimecmp, counting every clock) at CFG.io_base + CFG.timer.offset, 64 KiB, the
 * UART (rtl/lib/io/uart/uart_sifive: SiFive's map, div CFG.uart.div_rst after reset, its pins
 * uart_tx and uart_rx Mig3Cpu's) at CFG.io_base + CFG.uart.offset, 4 KiB: AddrDecode sends a
 * request there to them, any other to the memory (ReqDemux, the answers in order). The
 * core's loads and stores of the I/O region come as asked, a word at most (the D-cache's
 * no-cache requests), in the line format of the memory port: a device's
 * register port takes the word of the line the address names, and its answer goes into
 * every word of the line. The PLIC's sources are irq_src (the devices: the testbench) but
 * source CFG.timer.source, which is the Timer's interrupt (a peripheral timer: kb
 * rtl/design/mig3/timer), and CFG.uart.source, the UART's (kb rtl/design/mig3/uart); its
 * context 0 is the hart's machine mode: eip[0] is the core's
 * meip (kb rtl/design/mig3/plic).
 * Atomics (AMOs) are done in front of the memory, where every access to it meets
 * (AtomicUnit, kb rtl/lib/block/atomic/design): other requests pass, an AMO's word is
 * read, its new value written, and the old line answered. The PLIC takes no AMOs.
 * The debug port of the core is a port of Mig3Cpu: the testbench (or a semihosting
 * service) reads and writes registers while halted and resumes the core.
 *
 *   Mig3Core --mem_req--> AddrDecode --sel--> ReqDemux --+--> AtomicUnit --> SimLatencyRAM
 *                                                        |    (miss)
 *            <--mem_rsp--------------------------------- +--> word of the line --> Plic
 *                                                        +--> word of the line --> Timer
 *                                                        +--> word of the line --> UartSifive
 *            <--meip = eip[0] ------------------- Plic <-- irq_src, Timer's, UART's irq      |
 *                                                                        uart_tx, uart_rx <--+
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "dark_circuit_assert.svh"

module Mig3Cpu import Mig3Pkg::*; #(
    parameter mig3_cfg_t CFG = MIG3_CFG     // configuration, see Mig3ConfigPkg
)(
    input  wire                      clk,
    input  wire                      rst_n,     // synchronous reset, active low
    input  wire                      uncached,  // the core bypasses its caches, see Mig3Caches
    // Interrupts of the devices: the PLIC's sources, but CFG.timer.source and CFG.uart.source
    // (the Timer's, the UART's).
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire [CFG.plic.sources:1] irq_src,
    /* verilator lint_on UNUSEDSIGNAL */
    output wire                      uart_tx,   // the UART's pins
    input  wire                      uart_rx,
    output wire                      halt,      // core halted at EBREAK, see Mig3Core
    output retire_t                  retire,    // for trace in testbench
    output pipe_trace_t              pipe_trace, // pipeline view for testbench
    input  dbg_req_t                 dbg_req,   // debug, used while halted
    output dbg_rsp_t                 dbg_rsp
);
    localparam MEM_ADDR_WIDTH  = CFG.mem_addr_width;    // memory size: 1 << MEM_ADDR_WIDTH bytes
    localparam PLIC_ADDR_WIDTH = CFG.plic.addr_width;
    localparam TIMER_ADDR_WIDTH = TimerPkg::ADDR_BITS;
    localparam UART_ADDR_WIDTH  = UartSifivePkg::ADDR_BITS;

    `DC_STATIC_ASSERT(a_plic_in_io, CFG.plic.offset % (1 << PLIC_ADDR_WIDTH) == 0 &&
                      CFG.plic.offset + (1 << PLIC_ADDR_WIDTH) <= (1 << CFG.io_addr_width))
    `DC_STATIC_ASSERT(a_timer_in_io, CFG.timer.offset % (1 << TIMER_ADDR_WIDTH) == 0 &&
                      CFG.timer.offset + (1 << TIMER_ADDR_WIDTH) <= (1 << CFG.io_addr_width)
                      && CFG.timer.source >= 1 && CFG.timer.source <= CFG.plic.sources)
    `DC_STATIC_ASSERT(a_uart_in_io, CFG.uart.offset % (1 << UART_ADDR_WIDTH) == 0 &&
                      CFG.uart.offset + (1 << UART_ADDR_WIDTH) <= (1 << CFG.io_addr_width)
                      && CFG.uart.source >= 1 && CFG.uart.source <= CFG.plic.sources &&
                      CFG.uart.source != CFG.timer.source)

    mem_rsp_t mem_rsp;
    mem_req_t mem_req;
    wire      meip;             // the PLIC's notification to the hart's machine mode
    wire      sel_plic;         // the request is for the PLIC
    wire      sel_timer;        // ... for the Timer
    wire      sel_uart;         // ... for the UART
    wire      sel_mem;          // ... for the memory: no region of a device
    wire      mem_valid;        // the memory's request channel and answer
    wire      mem_ready;
    wire      mem_rsp_valid;
    line_t    mem_rsp_data;
    wire      ram_valid;        // behind AtomicUnit: the RAM's
    wire      ram_ready;
    wire      ram_we;
    // Not fully used: address bits above MEM_ADDR_WIDTH, the offset and the size (the
    // RAM moves lines with strobes).
    /* verilator lint_off UNUSEDSIGNAL */
    word_t    ram_addr;
    size_t    ram_size;
    /* verilator lint_on UNUSEDSIGNAL */
    line_t    ram_wdata;
    line_strb_t ram_wstrb;
    wire      ram_rsp_valid;
    line_t    ram_rsp_data;
    wire      plic_valid;       // the PLIC's register port
    wire      plic_ready;
    word_t    dev_wdata;        // a device's: the word of the line the address names
    strb_t    dev_wstrb;
    wire      plic_rsp_valid;
    word_t    plic_rdata;
    wire      timer_valid;      // the Timer's register port
    wire      timer_ready;
    wire      timer_rsp_valid;
    word_t    timer_rdata;
    wire      timer_irq;        // mtime >= mtimecmp
    wire      uart_valid;       // the UART's register port
    wire      uart_ready;
    wire      uart_rsp_valid;
    word_t    uart_rdata;
    wire      uart_irq;         // its watermarks
    wire [CFG.plic.sources:1] plic_src;     // irq_src, the Timer's and the UART's irq at theirs

    Mig3Core #(.CFG(CFG)) u_mig3_core(
        .clk, .rst_n, .uncached, .meip, .mem_req, .mem_rsp, .halt, .retire, .pipe_trace, .dbg_req,
        .dbg_rsp);

    // @kb: rtl/design/mig3/plic
    // Rule 0 the PLIC, rule 1 the Timer, rule 2 the UART ({rule 2, rule 1, rule 0}).
    AddrDecode #(.ADDR_WIDTH(WIDTH), .N_RULES(3),
                 .BASES({WIDTH'(CFG.io_base + CFG.uart.offset),
                         WIDTH'(CFG.io_base + CFG.timer.offset),
                         WIDTH'(CFG.io_base + CFG.plic.offset)}),
                 .WIDTHS({8'(UART_ADDR_WIDTH), 8'(TIMER_ADDR_WIDTH), 8'(PLIC_ADDR_WIDTH)}))
        u_addr_decode(.addr(mem_req.addr), .sel({sel_uart, sel_timer, sel_plic}), .miss(sel_mem));

    ReqDemux #(.N_TARGETS(4), .RSP_WIDTH($bits(line_t))) u_req_demux(
        .clk, .rst_n,
        .req_valid(mem_req.valid), .req_ready(mem_rsp.ready), .req_we(mem_req.we),
        .req_sel({sel_uart, sel_timer, sel_plic, sel_mem}), .rsp_valid(mem_rsp.valid),
        .rsp_data(mem_rsp.data),
        .tgt_req_valid({uart_valid, timer_valid, plic_valid, mem_valid}),
        .tgt_req_ready({uart_ready, timer_ready, plic_ready, mem_ready}),
        .tgt_rsp_valid({uart_rsp_valid, timer_rsp_valid, plic_rsp_valid, mem_rsp_valid}),
        .tgt_rsp_data({{LINE_WORDS{uart_rdata}}, {LINE_WORDS{timer_rdata}},
                       {LINE_WORDS{plic_rdata}}, mem_rsp_data}));

    // Atomics in front of the memory: the other requests pass as they come.
    // @kb: rtl/lib/block/atomic/design
    AtomicUnit #(.ADDR_WIDTH(WIDTH), .DATA_WIDTH($bits(line_t)), .ATOM_WIDTH(WIDTH),
                 .PENDING_WIDTH(1)) u_atomic_unit(
        .clk, .rst_n,
        .req_valid(mem_valid), .req_ready(mem_ready), .req_we(mem_req.we),
        .req_addr(mem_req.addr), .req_size(mem_req.size), .req_atop(mem_req.atop),
        .req_wdata(mem_req.wdata), .req_wstrb(mem_req.wstrb),
        .rsp_valid(mem_rsp_valid), .rsp_data(mem_rsp_data),
        .mem_req_valid(ram_valid), .mem_req_ready(ram_ready), .mem_req_we(ram_we),
        .mem_req_addr(ram_addr), .mem_req_size(ram_size), .mem_req_wdata(ram_wdata),
        .mem_req_wstrb(ram_wstrb), .mem_rsp_valid(ram_rsp_valid),
        .mem_rsp_data(ram_rsp_data));

    // The memory, code and data; latency 1, always ready.
    SimLatencyRAM #(.DATA_SIZE(LINE_SIZE), .ADDR_WIDTH(MEM_ADDR_WIDTH),
                    .READY_PERCENT(100), .FAST_PERCENT(100), .FAST_MIN(1), .FAST_MAX(1),
                    .MAX_PENDING(1)) u_mem(
        .clk, .rst_n,
        .req_valid(ram_valid), .req_ready(ram_ready), .req_we(ram_we),
        .req_addr({ram_addr[MEM_ADDR_WIDTH-1:LINE_START], {LINE_START{1'b0}}}),
        .req_wdata(ram_wdata), .req_wstrb(ram_wstrb),
        .rsp_valid(ram_rsp_valid), .rsp_data(ram_rsp_data));

    // A device's word: the one of the line the address names (a store's word is in every
    // word, its strobes only in its own).
    if (LINE_WORDS == 1) begin: g_one_word
        assign dev_wdata = mem_req.wdata;
        assign dev_wstrb = mem_req.wstrb;
    end else begin: g_words
        word_t [LINE_WORDS-1:0] words;
        strb_t [LINE_WORDS-1:0] strbs;
        assign words      = mem_req.wdata;
        assign strbs      = mem_req.wstrb;
        assign dev_wdata = words[mem_req.addr[LINE_START-1:DADDR_START]];
        assign dev_wstrb = strbs[mem_req.addr[LINE_START-1:DADDR_START]];
    end

    Plic #(.N_SOURCES(CFG.plic.sources), .N_CONTEXTS(1), .PRIO_WIDTH(CFG.plic.prio_width),
           .ADDR_WIDTH(PLIC_ADDR_WIDTH)) u_plic(
        .clk, .rst_n, .src(plic_src), .eip(meip),
        .req_valid(plic_valid), .req_ready(plic_ready), .req_we(mem_req.we),
        .req_addr(mem_req.addr[PLIC_ADDR_WIDTH-1:0]), .req_wdata(dev_wdata),
        .req_wstrb(dev_wstrb), .rsp_valid(plic_rsp_valid), .rsp_rdata(plic_rdata));

    // The Timer: mtime counts every clock; its interrupt is a PLIC source.
    // @kb: rtl/design/mig3/timer
    Timer #(.N_HARTS(1)) u_timer(
        .clk, .rst_n, .tick(1'b1), .irq(timer_irq),
        .req_valid(timer_valid), .req_ready(timer_ready), .req_we(mem_req.we),
        .req_addr(mem_req.addr[TIMER_ADDR_WIDTH-1:0]), .req_wdata(dev_wdata),
        .req_wstrb(dev_wstrb), .rsp_valid(timer_rsp_valid), .rsp_rdata(timer_rdata));

    // The UART: SiFive's, booting at div CFG.uart.div_rst; its interrupt is a PLIC source.
    // @kb: rtl/design/mig3/uart
    UartSifive #(.DIV_RST(UartSifivePkg::DIV_BITS'(CFG.uart.div_rst))) u_uart(
        .clk, .rst_n,
        .req_valid(uart_valid), .req_ready(uart_ready), .req_we(mem_req.we),
        .req_addr(mem_req.addr[UART_ADDR_WIDTH-1:0]), .req_wdata(dev_wdata),
        .req_wstrb(dev_wstrb), .rsp_valid(uart_rsp_valid), .rsp_rdata(uart_rdata),
        .tx(uart_tx), .rx(uart_rx), .irq(uart_irq));

    // The PLIC's sources: the devices', the Timer's and the UART's at theirs.
    for (genvar k = 1; k <= CFG.plic.sources; k++) begin: g_src
        if (k == CFG.timer.source) begin: g_timer
            assign plic_src[k] = timer_irq;
        end else if (k == CFG.uart.source) begin: g_uart
            assign plic_src[k] = uart_irq;
        end else begin: g_device
            assign plic_src[k] = irq_src[k];
        end
    end

    // No AMO to a device (no AtomicUnit there; a PMA fault in a later core).
    `DC_ASSERT(a_no_device_atomic,
        !(mem_req.valid && !sel_mem && AtomicPkg::is_atomic(mem_req.atop)))

    // Load the hex image into the memory, returns 1 when it is loaded.
    function automatic int load(string hex);
        return u_mem.load(hex, u_mem.VLOG_HEX_FORMAT);
    endfunction

endmodule

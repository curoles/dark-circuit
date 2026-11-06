/* Mig3 RISC-V CPU for simulation: Mig3Core with its memory.
 *
 * load() puts the hex image (objcopy -O verilog, see sw/riscv/mig3.ld) into the memory, one
 * SimLatencyRAM behind the memory port of the core (code and data: the caches inside the
 * core share it), a cache line (LINE_SIZE bytes) a request, with latency 1 and always ready
 * unless the testbench configures it (configure()). uncached=1 makes the core bypass its
 * caches. It has 1 << CFG.mem_addr_width
 * bytes; the core address bits above them are ignored, so addresses wrap around.
 * The debug port of the core is a port of Mig3Cpu: the testbench (or a semihosting
 * service) reads and writes registers while halted and resumes the core.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module Mig3Cpu import Mig3Pkg::*; #(
    parameter mig3_cfg_t CFG = MIG3_CFG     // configuration, see Mig3ConfigPkg
)(
    input  wire         clk,
    input  wire         rst_n,          // synchronous reset, active low
    input  wire         uncached,       // the core bypasses its caches, see Mig3Caches
    input  wire         meip,           // machine external interrupt: the testbench, a PLIC
                                        // later
    output wire         halt,           // core halted at EBREAK, see Mig3Core
    output retire_t     retire,         // for trace in testbench
    output pipe_trace_t pipe_trace,     // pipeline view for testbench
    input  dbg_req_t    dbg_req,        // debug, used while halted
    output dbg_rsp_t    dbg_rsp
);
    localparam MEM_ADDR_WIDTH = CFG.mem_addr_width;   // memory size: 1 << MEM_ADDR_WIDTH bytes

    mem_rsp_t mem_rsp;
    // Not fully used: address bits above MEM_ADDR_WIDTH (the memory wraps around), the
    // offset in the line and the size (the RAM moves lines).
    /* verilator lint_off UNUSEDSIGNAL */
    mem_req_t mem_req;
    /* verilator lint_on UNUSEDSIGNAL */

    Mig3Core #(.CFG(CFG)) u_mig3_core(
        .clk, .rst_n, .uncached, .meip, .mem_req, .mem_rsp, .halt, .retire, .pipe_trace, .dbg_req,
        .dbg_rsp);

    // The memory, code and data; latency 1, always ready.
    SimLatencyRAM #(.DATA_SIZE(LINE_SIZE), .ADDR_WIDTH(MEM_ADDR_WIDTH),
                    .READY_PERCENT(100), .FAST_PERCENT(100), .FAST_MIN(1), .FAST_MAX(1),
                    .MAX_PENDING(1)) u_mem(
        .clk, .rst_n,
        .req_valid(mem_req.valid), .req_ready(mem_rsp.ready), .req_we(mem_req.we),
        .req_addr({mem_req.addr[MEM_ADDR_WIDTH-1:LINE_START], {LINE_START{1'b0}}}),
        .req_wdata(mem_req.wdata), .req_wstrb(mem_req.wstrb),
        .rsp_valid(mem_rsp.valid), .rsp_data(mem_rsp.data));

    // Load the hex image into the memory, returns 1 when it is loaded.
    function automatic int load(string hex);
        return u_mem.load(hex, u_mem.VLOG_HEX_FORMAT);
    endfunction

endmodule

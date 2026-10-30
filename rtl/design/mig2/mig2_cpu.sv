/* Mig2 RISC-V CPU for simulation: Mig2Core with instruction and data memories.
 *
 * load() puts the same hex image (objcopy -O verilog, see sw/riscv/mig2.ld) into
 * instruction memory and data memory: code is fetched from imem, loads and stores go to
 * dmem. Both are SimLatencyRAM behind the memory channels of the core, for now with latency
 * 1 and always ready (what Mig2Core needs yet); imem is not written. Both have
 * 1 << CFG.mem_addr_width bytes; the core address bits above them are ignored, so addresses
 * wrap around.
 * The debug port of the core is a port of Mig2Cpu: the testbench (or a semihosting
 * service) reads and writes registers while halted and resumes the core.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module Mig2Cpu import Mig2Pkg::*; #(
    parameter mig2_cfg_t CFG = MIG2_CFG     // configuration, see Mig2ConfigPkg
)(
    input  wire         clk,
    input  wire         rst_n,          // synchronous reset, active low
    output wire         halt,           // core halted at EBREAK, see Mig2Core
    output retire_t     retire,         // for trace in testbench
    output pipe_trace_t pipe_trace,     // pipeline view for testbench
    input  dbg_req_t    dbg_req,        // debug, used while halted
    output dbg_rsp_t    dbg_rsp
);
    localparam MEM_ADDR_WIDTH = CFG.mem_addr_width;   // memory size: 1 << MEM_ADDR_WIDTH bytes

    imem_rsp_t imem_rsp;
    dmem_rsp_t dmem_rsp;
    // Not fully used: address bits above MEM_ADDR_WIDTH (memories wrap around).
    /* verilator lint_off UNUSEDSIGNAL */
    imem_req_t imem_req;
    dmem_req_t dmem_req;
    /* verilator lint_on UNUSEDSIGNAL */

    Mig2Core #(.CFG(CFG)) u_mig2_core(
        .clk, .rst_n, .imem_req, .imem_rsp, .dmem_req, .dmem_rsp, .halt, .retire, .pipe_trace,
        .dbg_req, .dbg_rsp);

    // Instruction memory, read only; latency 1, always ready.
    SimLatencyRAM #(.DATA_SIZE($bits(insn_t) / 8), .ADDR_WIDTH(MEM_ADDR_WIDTH),
                    .READY_PERCENT(100), .FAST_PERCENT(100), .FAST_MIN(1), .FAST_MAX(1),
                    .MAX_PENDING(1)) u_imem(
        .clk, .rst_n,
        .req_valid(imem_req.valid), .req_ready(imem_rsp.ready), .req_we(1'b0),
        .req_addr({imem_req.addr[MEM_ADDR_WIDTH-1:IADDR_START], {IADDR_START{1'b0}}}),
        .req_wdata('0), .req_wstrb('0),
        .rsp_valid(imem_rsp.valid), .rsp_data(imem_rsp.data));

    // Data memory; latency 1, always ready.
    SimLatencyRAM #(.DATA_SIZE(STRB_WIDTH), .ADDR_WIDTH(MEM_ADDR_WIDTH),
                    .READY_PERCENT(100), .FAST_PERCENT(100), .FAST_MIN(1), .FAST_MAX(1),
                    .MAX_PENDING(1)) u_dmem(
        .clk, .rst_n,
        .req_valid(dmem_req.valid), .req_ready(dmem_rsp.ready), .req_we(dmem_req.we),
        .req_addr({dmem_req.addr[MEM_ADDR_WIDTH-1:DADDR_START], {DADDR_START{1'b0}}}),
        .req_wdata(dmem_req.wdata), .req_wstrb(dmem_req.wstrb),
        .rsp_valid(dmem_rsp.valid), .rsp_data(dmem_rsp.data));

    // Load hex image into imem and dmem, returns 1 when both are loaded.
    function automatic int load(string hex);
        int ok_imem;
        int ok_dmem;
        ok_imem = u_imem.load(hex, u_imem.VLOG_HEX_FORMAT);
        ok_dmem = u_dmem.load(hex, u_dmem.VLOG_HEX_FORMAT);
        return ok_imem & ok_dmem;
    endfunction

endmodule

/* Mig1 RISC-V CPU for simulation: Mig1Core with instruction and data memories.
 *
 * load() puts the same hex image (objcopy -O verilog, see sw/riscv/mig1.ld) into
 * instruction memory (SimROM) and data memory (SimRAM): code is fetched from imem,
 * loads and stores go to dmem. Both have 1 << CFG.mem_addr_width bytes; the core address
 * bits above them are ignored, so addresses wrap around.
 * The debug port of the core is a port of Mig1Cpu: the testbench (or a semihosting
 * service) reads and writes registers while halted and resumes the core.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module Mig1Cpu import Mig1Pkg::*; #(
    parameter mig1_cfg_t CFG = MIG1_CFG     // configuration, see Mig1ConfigPkg
)(
    input  wire      clk,
    input  wire      rst_n,          // synchronous reset, active low
    output wire      halt,           // core halted at EBREAK, see Mig1Core
    output retire_t  retire,         // for trace in testbench
    input  dbg_req_t dbg_req,        // debug, used while halted
    output dbg_rsp_t dbg_rsp
);
    localparam MEM_ADDR_WIDTH = CFG.mem_addr_width;   // memory size: 1 << MEM_ADDR_WIDTH bytes

    imem_rsp_t imem_rsp;
    dmem_rsp_t dmem_rsp;
    // Not fully used: address bits above MEM_ADDR_WIDTH (memories wrap around),
    // rd_valid of dmem (the core knows the read latency).
    /* verilator lint_off UNUSEDSIGNAL */
    imem_req_t imem_req;
    dmem_req_t dmem_req;
    logic      dmem_rd_valid;
    /* verilator lint_on UNUSEDSIGNAL */

    Mig1Core #(.CFG(CFG)) u_mig1_core(
        .clk, .rst_n, .imem_req, .imem_rsp, .dmem_req, .dmem_rsp, .halt, .retire, .dbg_req,
        .dbg_rsp);

    // Instruction memory, read only.
    SimROM #(.DATA_SIZE($bits(insn_t) / 8), .ADDR_WIDTH(MEM_ADDR_WIDTH)) u_imem(
        .clk,
        .en(imem_req.en), .addr(imem_req.addr[MEM_ADDR_WIDTH-1:IADDR_START]),
        .data(imem_rsp.data));

    // Data memory.
    SimRAM #(.DATA_SIZE(STRB_WIDTH), .ADDR_WIDTH(MEM_ADDR_WIDTH)) u_dmem(
        .clk,
        .rd_en(dmem_req.rd_en), .rd_addr(dmem_req.addr[MEM_ADDR_WIDTH-1:DADDR_START]),
        .wr_en(dmem_req.wr_en), .wr_addr(dmem_req.addr[MEM_ADDR_WIDTH-1:DADDR_START]),
        .wr_data(dmem_req.wr_data), .wr_strb(dmem_req.wr_strb),
        .rd_data(dmem_rsp.rd_data), .rd_valid(dmem_rd_valid));

    // Load hex image into imem and dmem, returns 1 when both are loaded.
    function automatic int load(string hex);
        int ok_imem;
        int ok_dmem;
        ok_imem = u_imem.load(hex, u_imem.VLOG_HEX_FORMAT);
        ok_dmem = u_dmem.load(hex, u_dmem.VLOG_HEX_FORMAT);
        return ok_imem & ok_dmem;
    endfunction

endmodule

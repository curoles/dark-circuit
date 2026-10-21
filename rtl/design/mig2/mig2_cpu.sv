/* Mig2 RISC-V CPU for simulation: Mig2Core with instruction and data memories.
 *
 * load() puts the same hex image (objcopy -O verilog, see sw/riscv/mig2.ld) into
 * instruction memory (SimROM) and data memory (SimRAM): code is fetched from imem,
 * loads and stores go to dmem. Both have 1 << CFG.mem_addr_width bytes; the core address
 * bits above them are ignored, so addresses wrap around.
 * The debug port of the core is a port of Mig2Cpu: the testbench (or a semihosting
 * service) reads and writes registers while halted and resumes the core.
 */
module Mig2Cpu import Mig2Pkg::*; #(
    parameter mig2_cfg_t CFG = MIG2_CFG     // configuration, see Mig2ConfigPkg
)(
    input  wire      clk,
    input  wire      rst_n,          // synchronous reset, active low
    output wire      halt,           // core halted at EBREAK, see Mig2Core
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
    wire       dmem_rd_valid;
    /* verilator lint_on UNUSEDSIGNAL */

    Mig2Core #(.CFG(CFG)) u_mig2_core(
        .clk(clk), .rst_n(rst_n),
        .imem_req(imem_req), .imem_rsp(imem_rsp),
        .dmem_req(dmem_req), .dmem_rsp(dmem_rsp),
        .halt(halt), .retire(retire),
        .dbg_req(dbg_req), .dbg_rsp(dbg_rsp));

    // Instruction memory, read only.
    SimROM #(.DATA_SIZE(INSN_WIDTH / 8), .ADDR_WIDTH(MEM_ADDR_WIDTH)) u_imem(
        .clk(clk),
        .en(imem_req.en), .addr(imem_req.addr[MEM_ADDR_WIDTH-1:IADDR_START]),
        .data(imem_rsp.data));

    // Data memory.
    SimRAM #(.DATA_SIZE(STRB_WIDTH), .ADDR_WIDTH(MEM_ADDR_WIDTH)) u_dmem(
        .clk(clk),
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

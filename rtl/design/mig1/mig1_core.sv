/* Mig1 RISC-V RV32I core, synthesizable, memories are outside.
 *
 * Instruction fetch and data access have 1 clock read latency, like SimROM,
 * SimRAM, SRAM and FPGA block RAM. The core stops (halt=1) on EBREAK, ECALL or an
 * illegal instruction; illegal=1 tells that it can not continue. While halted,
 * the debug port reads and writes registers, and resume continues after EBREAK.
 *
 * Mig1Core only connects its parts: Mig1Fetch (PC, imem requests),
 * Mig1Control (run, halt); more parts come with decode, registers, ALU,
 * branches and loads/stores. Pipeline: IF fetches, EX executes the instruction
 * that arrives from imem; parts do not depend on that, so they fit a 5-stage pipeline too.
 * TODO: for now instructions are not executed, they only retire; the core halts at EBREAK.
 */
module Mig1Core import Mig1Pkg::*; #(
    parameter RST_ADDR = MIG1_RST_ADDR     // PC after reset, byte address
)(
    input  wire       clk,
    input  wire       rst_n,               // synchronous reset, active low

    output imem_req_t imem_req,
    input  imem_rsp_t imem_rsp,
    output dmem_req_t dmem_req,
    input  dmem_rsp_t dmem_rsp,

    output wire       halt,                // core stopped: EBREAK, ECALL or illegal
    output wire       illegal,             // stopped by ECALL, illegal instruction
                                           // or jump to address not divisible by 4
    output retire_t   retire,

    input  dbg_req_t  dbg_req,
    output dbg_rsp_t  dbg_rsp
);

    fetch_ctrl_t fetch_ctrl;
    fetch_t      ex;        // instruction in EX: arrives from imem in this cycle
    insn_t       ex_insn;
    iaddr_t      halt_pc;

    assign ex_insn = imem_rsp.data;

    Mig1Fetch #(.RST_ADDR(RST_ADDR)) u_mig1_fetch(
        .clk(clk), .rst_n(rst_n), .ctrl(fetch_ctrl), .imem_req(imem_req), .fetch(ex));

    Mig1Control u_mig1_control(
        .clk(clk), .rst_n(rst_n), .ex(ex), .ex_insn(ex_insn),
        .fetch_ctrl(fetch_ctrl), .halt(halt), .halt_pc(halt_pc));

    // Every instruction in EX retires without doing anything yet, no register is written.
    assign retire.valid   = ex.valid;
    assign retire.pc      = ex.pc;
    assign retire.insn    = ex_insn;
    assign retire.rd      = '0;
    assign retire.rd_data = '0;

    assign dbg_rsp.halt_pc   = halt_pc;
    assign dbg_rsp.reg_rdata = '0;

    // TODO: data memory (loads and stores), illegal (decode), debug register access.
    assign dmem_req = '0;
    assign illegal  = 1'b0;
    /* verilator lint_off UNUSEDSIGNAL */
    wire stub_unused = &{1'b0, dmem_rsp, dbg_req};
    /* verilator lint_on UNUSEDSIGNAL */

endmodule

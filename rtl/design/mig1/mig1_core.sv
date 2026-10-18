/* Mig1 RISC-V RV32I core, synthesizable, memories are outside.
 *
 * Instruction fetch and data access have 1 clock read latency, like SimROM,
 * SimRAM, SRAM and FPGA block RAM. The core stops (halt=1) on EBREAK, ECALL or an
 * illegal instruction; illegal=1 tells that it can not continue. While halted,
 * the debug port reads and writes registers, and resume continues after EBREAK.
 *
 * Mig1Core only connects its parts: Mig1Fetch (PC, imem requests),
 * Mig1Control (run, redirect, halt), Mig1Decode, Mig1Regs, Mig1Alu, Mig1Branch;
 * Mig1Lsu comes with loads/stores. Pipeline: IF fetches, EX executes the instruction
 * that arrives from imem; parts do not depend on that, so they fit a 5-stage pipeline too.
 * A taken branch or jump costs one bubble: the instruction fetched after it is dropped.
 * TODO: loads, stores, FENCE and ECALL retire without effect, the core halts at EBREAK.
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
    fetch_t      ex;            // instruction in EX: arrives from imem in this cycle
    insn_t       ex_insn;
    logic        ex_done;       // instruction in EX completes: writes rd, retires
    iaddr_t      halt_pc;
    decoded_t    dec;           // instruction in EX taken apart
    word_t       rs1_data;
    word_t       rs2_data;
    word_t       alu_result;
    branch_t     branch;
    word_t       link;          // pc + 4 for JAL, JALR
    logic        rd_write;      // instruction in EX writes rd in this cycle
    word_t       rd_data;
    word_t       dbg_reg_rdata;

    assign ex_insn = imem_rsp.data;

    Mig1Fetch #(.RST_ADDR(RST_ADDR)) u_mig1_fetch(
        .clk(clk), .rst_n(rst_n), .ctrl(fetch_ctrl), .imem_req(imem_req), .fetch(ex));

    Mig1Control u_mig1_control(
        .clk(clk), .rst_n(rst_n), .ex(ex), .ex_insn(ex_insn), .branch(branch),
        .fetch_ctrl(fetch_ctrl), .ex_done(ex_done), .halt(halt), .illegal(illegal),
        .halt_pc(halt_pc));

    Mig1Decode u_mig1_decode(.insn(ex_insn), .dec(dec));

    Mig1Regs u_mig1_regs(
        .clk(clk), .halt(halt),
        .rs1(dec.rs1), .rs2(dec.rs2), .rs1_data(rs1_data), .rs2_data(rs2_data),
        .rd_we(rd_write), .rd(dec.rd), .rd_data(rd_data),
        .dbg_reg_addr(dbg_req.reg_addr), .dbg_reg_wr(dbg_req.reg_wr),
        .dbg_reg_wdata(dbg_req.reg_wdata), .dbg_reg_rdata(dbg_reg_rdata));

    Mig1Alu u_mig1_alu(
        .dec(dec), .pc(ex.pc), .rs1_data(rs1_data), .rs2_data(rs2_data), .result(alu_result));

    Mig1Branch u_mig1_branch(
        .dec(dec), .pc(ex.pc), .rs1_data(rs1_data), .rs2_data(rs2_data),
        .branch(branch), .link(link));

    // Kinds executed so far write rd: JAL and JALR the link, others the ALU result.
    // Loads write rd too (dec.rd_we), they come with loads/stores.
    assign rd_write = ex_done && (dec.kind == KIND_OP  || dec.kind == KIND_OP_IMM ||
                                  dec.kind == KIND_LUI || dec.kind == KIND_AUIPC ||
                                  dec.kind == KIND_JAL || dec.kind == KIND_JALR);
    assign rd_data  = (dec.kind == KIND_JAL || dec.kind == KIND_JALR) ? link : alu_result;

    // Retire: rd and rd_data are 0 when no register is written, also for writes to x0 (as RVFI).
    assign retire.valid   = ex_done;
    assign retire.pc      = ex.pc;
    assign retire.insn    = ex_insn;
    assign retire.rd      = (rd_write && dec.rd != '0) ? dec.rd : '0;
    assign retire.rd_data = (rd_write && dec.rd != '0) ? rd_data : '0;

    assign dbg_rsp.halt_pc   = halt_pc;
    assign dbg_rsp.reg_rdata = dbg_reg_rdata;

    // TODO: data memory (loads and stores), resume.
    assign dmem_req = '0;
    /* verilator lint_off UNUSEDSIGNAL */
    wire stub_unused = &{1'b0, dmem_rsp, dbg_req.resume};
    /* verilator lint_on UNUSEDSIGNAL */

endmodule

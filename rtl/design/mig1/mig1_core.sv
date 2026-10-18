/* Mig1 RISC-V RV32I core, synthesizable, memories are outside.
 *
 * Instruction fetch and data access have 1 clock read latency, like SimROM,
 * SimRAM, SRAM and FPGA block RAM. The core stops (halt=1) on EBREAK, and on a fault
 * (ECALL, illegal instruction, misaligned jump target or load/store address); then
 * illegal=1 tells that it can not continue. While halted, the debug port reads and
 * writes registers, and resume continues after EBREAK.
 *
 * Mig1Core only connects its parts: Mig1Fetch (PC, imem requests),
 * Mig1Control (run, stall, redirect, halt), Mig1Decode, Mig1Regs, Mig1Alu,
 * Mig1Branch, Mig1Lsu (dmem requests). Pipeline: IF fetches, EX executes the
 * instruction that arrives from imem; parts do not depend on that, so they fit
 * a 5-stage pipeline too. Signals of a stage have its prefix: if_, ex_.
 * A taken branch or jump costs one bubble: the instruction fetched after it is dropped.
 * A load stays 2 cycles in EX: it waits for dmem data.
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
    output wire       illegal,             // stopped by ECALL, illegal instruction,
                                           // jump to address not divisible by 4
                                           // or misaligned load/store
    output retire_t   retire,

    input  dbg_req_t  dbg_req,
    output dbg_rsp_t  dbg_rsp
);

    fetch_ctrl_t if_ctrl;           // Control -> Fetch
    fetch_t      ex_fetch;          // instruction in EX: valid, pc; arrives from imem
    insn_t       ex_insn;
    decoded_t    ex_dec;            // instruction in EX taken apart
    word_t       ex_rs1_data;
    word_t       ex_rs2_data;
    word_t       ex_alu_result;     // also the load/store address rs1 + imm
    branch_t     ex_branch;
    word_t       ex_link;           // pc + 4 for JAL, JALR
    lsu_t        ex_lsu;
    word_t       ex_load_data;
    logic        ex_done;           // instruction in EX completes: writes rd, retires
    logic        ex_rd_write;       // instruction in EX writes rd in this cycle
    rd_src_t     ex_rd_src;
    word_t       ex_rd_data;
    iaddr_t      halt_pc;
    word_t       dbg_reg_rdata;

    assign ex_insn = imem_rsp.data;

    Mig1Fetch #(.RST_ADDR(RST_ADDR)) u_mig1_fetch(
        .clk(clk), .rst_n(rst_n), .ctrl(if_ctrl), .imem_req(imem_req), .fetch(ex_fetch));

    Mig1Control u_mig1_control(
        .clk(clk), .rst_n(rst_n), .ex(ex_fetch), .ex_dec(ex_dec), .branch(ex_branch),
        .lsu(ex_lsu), .resume(dbg_req.resume), .fetch_ctrl(if_ctrl), .ex_done(ex_done),
        .halt(halt), .illegal(illegal), .halt_pc(halt_pc));

    Mig1Decode u_mig1_decode(.insn(ex_insn), .dec(ex_dec));

    Mig1Regs u_mig1_regs(
        .clk(clk), .halt(halt),
        .rs1(ex_dec.rs1), .rs2(ex_dec.rs2), .rs1_data(ex_rs1_data), .rs2_data(ex_rs2_data),
        .rd_we(ex_rd_write), .rd(ex_dec.rd), .rd_data(ex_rd_data),
        .dbg_reg_addr(dbg_req.reg_addr), .dbg_reg_wr(dbg_req.reg_wr),
        .dbg_reg_wdata(dbg_req.reg_wdata), .dbg_reg_rdata(dbg_reg_rdata));

    Mig1Alu u_mig1_alu(
        .dec(ex_dec), .pc(ex_fetch.pc), .rs1_data(ex_rs1_data), .rs2_data(ex_rs2_data),
        .result(ex_alu_result));

    Mig1Branch u_mig1_branch(
        .dec(ex_dec), .pc(ex_fetch.pc), .rs1_data(ex_rs1_data), .rs2_data(ex_rs2_data),
        .branch(ex_branch), .link(ex_link));

    Mig1Lsu u_mig1_lsu(
        .clk(clk), .rst_n(rst_n), .valid(ex_fetch.valid), .dec(ex_dec),
        .addr(ex_alu_result), .rs2_data(ex_rs2_data),
        .dmem_req(dmem_req), .dmem_rsp(dmem_rsp), .lsu(ex_lsu), .load_data(ex_load_data));

    // Write back: decode tells whether rd is written and where its value comes from.
    // ex_rd_src with assign: Icarus does not support selects of ex_dec in always_comb.
    assign ex_rd_write = ex_done && ex_dec.rd_we;
    assign ex_rd_src   = ex_dec.rd_src;

    always_comb
        case (ex_rd_src)
            RD_LINK: ex_rd_data = ex_link;
            RD_LOAD: ex_rd_data = ex_load_data;
            default: ex_rd_data = ex_alu_result;
        endcase

    // Retire: rd and rd_data are 0 when no register is written, also for writes to x0 (as RVFI).
    assign retire.valid   = ex_done;
    assign retire.pc      = ex_fetch.pc;
    assign retire.insn    = ex_insn;
    assign retire.rd      = (ex_rd_write && ex_dec.rd != '0) ? ex_dec.rd : '0;
    assign retire.rd_data = (ex_rd_write && ex_dec.rd != '0) ? ex_rd_data : '0;

    assign dbg_rsp.halt_pc   = halt_pc;
    assign dbg_rsp.reg_rdata = dbg_reg_rdata;

endmodule

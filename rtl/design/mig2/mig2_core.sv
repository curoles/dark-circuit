/* Mig2 RISC-V RV32I core, synthesizable, memories are outside.
 *
 * Instruction fetch and data access have 1 clock read latency, like SimROM,
 * SimRAM, SRAM and FPGA block RAM. Faults (ECALL, illegal instruction, misaligned
 * jump target or load/store address, ...) trap to mtvec in machine mode, MRET returns.
 * EBREAK traps too, or halts the core (halt=1) when the debugger sets
 * dbg_req.ebreak_halt; while halted, the debug port reads and writes registers, and
 * resume continues after EBREAK.
 *
 * Mig2Core only connects its parts: Mig2Fetch (PC, imem requests),
 * Mig2Control (run, stall, redirect, traps, halt), Mig2Decode, Mig2Regs, Mig2Alu,
 * Mig2Branch, Mig2Lsu (dmem requests), Mig2LoadData, Mig2Csr, Mig2MulDiv,
 * Mig2Forward, Mig2Pipe (pipeline registers).
 * Pipeline IF | ID | EX | MEM/WB: IF fetches; ID decodes the instruction that arrives
 * from imem and reads its registers; EX executes: branches, traps, CSRs and stores
 * happen there, loads send their read; MEM/WB gets load data, writes rd and retires.
 * An instruction that leaves EX always completes. Signals of a stage have its prefix:
 * if_, id_, ex_, mem_.
 * A taken branch or jump, a trap and MRET cost two bubbles: the instructions in ID and
 * IF are dropped. Results are forwarded to ID (Mig2Forward); an instruction that reads
 * the rd of a load right before it waits one cycle in ID (load-use).
 * A division stays 34 cycles in EX.
 */
module Mig2Core import Mig2Pkg::*; #(
    parameter RST_ADDR = MIG2_RST_ADDR     // PC after reset, byte address
)(
    input  wire       clk,
    input  wire       rst_n,               // synchronous reset, active low

    output imem_req_t imem_req,
    input  imem_rsp_t imem_rsp,
    output dmem_req_t dmem_req,
    input  dmem_rsp_t dmem_rsp,

    output wire       halt,                // core halted at EBREAK, see dbg_req.ebreak_halt
    output retire_t   retire,              // RVFI trace, see Mig2Pkg

    input  dbg_req_t  dbg_req,
    output dbg_rsp_t  dbg_rsp
);

    fetch_ctrl_t if_ctrl;           // Control -> Fetch
    pipe_ctrl_t  pipe_ctrl;         // Control -> Pipe
    fetch_t      id_fetch;          // instruction in ID: valid, pc; arrives from imem
    insn_t       id_insn;
    decoded_t    id_dec;            // instruction in ID taken apart
    word_t       id_rf_rs1_data;    // register file values; id_rs1_data has forwarding
    word_t       id_rf_rs2_data;
    word_t       id_rs1_data;
    word_t       id_rs2_data;
    id_ex_t      id_ex_d;
    id_ex_t      id_ex_q;
    fetch_t      ex_fetch;          // instruction in EX: valid, pc
    insn_t       ex_insn;
    decoded_t    ex_dec;            // instruction in EX taken apart
    word_t       ex_rs1_data;
    word_t       ex_rs2_data;
    word_t       ex_alu_result;     // also the load/store address rs1 + imm
    branch_t     ex_branch;
    word_t       ex_link;           // pc + 4 for JAL, JALR
    logic        ex_lsu_misaligned;
    lsu_mem_t    ex_lsu_mem;        // memory access, for retire
    byte_offset_t ex_load_offset;   // byte of the load address in the word
    word_t       ex_csr_rdata;      // old value of the CSR of a CSR instruction
    logic        ex_csr_illegal;
    word_t       ex_muldiv_result;  // product, quotient or remainder of an M instruction
    logic        ex_muldiv_stall;
    logic        ex_done;           // instruction in EX completes: CSR write and minstret
                                    // now, rd and retire in MEM/WB
    trap_t       ex_trap;           // instruction in EX faults: retires as a trap
    csr_t        ex_csr;            // mtvec, mepc
    logic        ex_rd_write;       // instruction in EX will write rd
    reg_id_t     ex_rd;             // rd written by the instruction in EX, 0 when none
    rd_src_t     ex_rd_src;
    word_t       ex_rd_data;
    retire_t     ex_retire;         // RVFI entry built in EX, completed in MEM/WB
    ex_mem_t     ex_mem_d;
    ex_mem_t     ex_mem_q;
    // order and mem_rdata of mem_ret are not used: MEM/WB fills them.
    /* verilator lint_off UNUSEDSIGNAL */
    retire_t     mem_ret;           // instruction in MEM/WB: its entry from EX
    /* verilator lint_on UNUSEDSIGNAL */
    word_t       mem_load_data;
    reg_id_t     mem_rd;            // rd written in MEM/WB, 0 when none
    logic        mem_rd_write;
    word_t       mem_rd_data;
    iaddr_t      halt_pc;
    word_t       dbg_reg_rdata;
    logic [63:0] retire_order;      // number of instructions retired so far

    // IF
    Mig2Fetch #(.RST_ADDR(RST_ADDR)) u_mig2_fetch(
        .clk(clk), .rst_n(rst_n), .ctrl(if_ctrl), .imem_req(imem_req), .fetch(id_fetch));

    Mig2Control u_mig2_control(
        .clk, .rst_n, .id_valid(id_fetch.valid), .id_dec, .ex(ex_fetch), .ex_insn, .ex_dec,
        .ex_addr(ex_alu_result), .branch(ex_branch), .lsu_misaligned(ex_lsu_misaligned),
        .csr_illegal(ex_csr_illegal), .muldiv_stall(ex_muldiv_stall), .csr(ex_csr),
        .ebreak_halt(dbg_req.ebreak_halt), .resume(dbg_req.resume), .fetch_ctrl(if_ctrl),
        .pipe_ctrl, .ex_done, .ex_trap, .halt, .halt_pc);

    // ID
    assign id_insn = imem_rsp.data;

    Mig2Decode u_mig2_decode(.insn(id_insn), .dec(id_dec));

    Mig2Regs u_mig2_regs(
        .clk(clk), .halt(halt),
        .rs1(id_dec.rs1), .rs2(id_dec.rs2), .rs1_data(id_rf_rs1_data), .rs2_data(id_rf_rs2_data),
        .rd_we(mem_rd_write), .rd(mem_rd), .rd_data(mem_rd_data),
        .dbg_reg_id(dbg_req.reg_id), .dbg_reg_wr(dbg_req.reg_wr),
        .dbg_reg_wdata(dbg_req.reg_wdata), .dbg_reg_rdata(dbg_reg_rdata));

    Mig2Forward u_mig2_forward(
        .rs1(id_dec.rs1), .rs2(id_dec.rs2), .rf_rs1_data(id_rf_rs1_data),
        .rf_rs2_data(id_rf_rs2_data), .ex_rd, .ex_rd_data, .mem_rd, .mem_rd_data,
        .rs1_data(id_rs1_data), .rs2_data(id_rs2_data));

    assign id_ex_d.valid    = id_fetch.valid;
    assign id_ex_d.pc       = id_fetch.pc;
    assign id_ex_d.insn     = id_insn;
    assign id_ex_d.dec      = id_dec;
    assign id_ex_d.rs1_data = id_rs1_data;
    assign id_ex_d.rs2_data = id_rs2_data;

    Mig2Pipe u_mig2_pipe(.clk, .rst_n, .ctrl(pipe_ctrl), .id_ex_d, .id_ex_q, .ex_mem_d, .ex_mem_q);

    // EX
    assign ex_fetch.valid = id_ex_q.valid;
    assign ex_fetch.pc    = id_ex_q.pc;
    assign ex_insn        = id_ex_q.insn;
    assign ex_dec         = id_ex_q.dec;
    assign ex_rs1_data    = id_ex_q.rs1_data;
    assign ex_rs2_data    = id_ex_q.rs2_data;

    Mig2Alu u_mig2_alu(
        .dec(ex_dec), .pc(ex_fetch.pc), .rs1_data(ex_rs1_data), .rs2_data(ex_rs2_data),
        .result(ex_alu_result));

    Mig2Branch u_mig2_branch(
        .dec(ex_dec), .pc(ex_fetch.pc), .rs1_data(ex_rs1_data), .rs2_data(ex_rs2_data),
        .branch(ex_branch), .link(ex_link));

    Mig2Lsu u_mig2_lsu(
        .valid(ex_fetch.valid), .dec(ex_dec), .addr(ex_alu_result), .rs2_data(ex_rs2_data),
        .dmem_req, .misaligned(ex_lsu_misaligned), .mem(ex_lsu_mem));

    assign ex_load_offset = ex_alu_result[DADDR_START-1:0];

    Mig2Csr u_mig2_csr(
        .clk, .rst_n, .valid(ex_fetch.valid), .done(ex_done), .dec(ex_dec),
        .rs1_data(ex_rs1_data), .pc(ex_fetch.pc), .trap(ex_trap), .rdata(ex_csr_rdata),
        .illegal(ex_csr_illegal), .csr(ex_csr));

    Mig2MulDiv u_mig2_muldiv(
        .clk, .rst_n, .valid(ex_fetch.valid), .dec(ex_dec), .rs1_data(ex_rs1_data),
        .rs2_data(ex_rs2_data), .stall(ex_muldiv_stall), .result(ex_muldiv_result));

    // rd value: decode tells whether rd is written and where its value comes from.
    // ex_rd_src with assign: Icarus does not support selects of ex_dec in always_comb.
    assign ex_rd_write = ex_done && ex_dec.rd_we;
    assign ex_rd       = (ex_fetch.valid && ex_dec.rd_we) ? ex_dec.rd : '0;
    assign ex_rd_src   = ex_dec.rd_src;

    always_comb
        case (ex_rd_src)
            RD_LINK:   ex_rd_data = ex_link;
            RD_CSR:    ex_rd_data = ex_csr_rdata;
            RD_MULDIV: ex_rd_data = ex_muldiv_result;
            default:   ex_rd_data = ex_alu_result;      // loads: MEM/WB replaces it
        endcase

    // Retire entry, RVFI: an instruction that completes or traps; fields it does not
    // use are 0. MEM/WB adds order, and the load data.
    assign ex_retire.valid     = ex_done || ex_trap.valid;
    assign ex_retire.order     = '0;
    assign ex_retire.insn      = ex_insn;
    assign ex_retire.trap      = ex_trap.valid;
    assign ex_retire.pc_rdata  = {ex_fetch.pc, {IADDR_START{1'b0}}};
    assign ex_retire.pc_wdata  = if_ctrl.redirect ? {if_ctrl.target, {IADDR_START{1'b0}}} : ex_link;
    assign ex_retire.rs1_addr  = ex_dec.uses_rs1 ? ex_dec.rs1 : '0;
    assign ex_retire.rs1_rdata = ex_dec.uses_rs1 ? ex_rs1_data : '0;
    assign ex_retire.rs2_addr  = ex_dec.uses_rs2 ? ex_dec.rs2 : '0;
    assign ex_retire.rs2_rdata = ex_dec.uses_rs2 ? ex_rs2_data : '0;
    assign ex_retire.rd_addr   = (ex_rd_write && ex_dec.rd != '0) ? ex_dec.rd : '0;
    assign ex_retire.rd_wdata  = (ex_rd_write && ex_dec.rd != '0) ? ex_rd_data : '0;
    assign ex_retire.mem_addr  = ex_lsu_mem.addr;
    assign ex_retire.mem_rmask = ex_lsu_mem.rmask;
    assign ex_retire.mem_wmask = ex_lsu_mem.wmask;
    assign ex_retire.mem_rdata = '0;
    assign ex_retire.mem_wdata = ex_lsu_mem.wdata;

    assign ex_mem_d.ret    = ex_retire;
    assign ex_mem_d.load   = ex_rd_src == RD_LOAD;
    assign ex_mem_d.funct3 = ex_dec.funct3;
    assign ex_mem_d.offset = ex_load_offset;

    // MEM/WB
    assign mem_ret = ex_mem_q.ret;

    Mig2LoadData u_mig2_load_data(
        .funct3(ex_mem_q.funct3), .offset(ex_mem_q.offset), .word(dmem_rsp.rd_data),
        .load_data(mem_load_data));

    // Write back: rd_addr of the entry is 0 when nothing is written (RVFI): bubbles,
    // traps, x0; EX builds it from ex_done.
    assign mem_rd       = mem_ret.rd_addr;
    assign mem_rd_write = mem_rd != '0;
    assign mem_rd_data  = ex_mem_q.load ? mem_load_data : mem_ret.rd_wdata;

    // Retire, RVFI: the entry from EX with order, and load data.
    always_ff @(posedge clk)
        if (!rst_n)            retire_order <= '0;
        else if (retire.valid) retire_order <= retire_order + 1'b1;

    assign retire.valid     = mem_ret.valid;
    assign retire.order     = retire_order;
    assign retire.insn      = mem_ret.insn;
    assign retire.trap      = mem_ret.trap;
    assign retire.pc_rdata  = mem_ret.pc_rdata;
    assign retire.pc_wdata  = mem_ret.pc_wdata;
    assign retire.rs1_addr  = mem_ret.rs1_addr;
    assign retire.rs1_rdata = mem_ret.rs1_rdata;
    assign retire.rs2_addr  = mem_ret.rs2_addr;
    assign retire.rs2_rdata = mem_ret.rs2_rdata;
    assign retire.rd_addr   = mem_ret.rd_addr;
    assign retire.rd_wdata  = mem_rd_write ? mem_rd_data : '0;
    assign retire.mem_addr  = mem_ret.mem_addr;
    assign retire.mem_rmask = mem_ret.mem_rmask;
    assign retire.mem_wmask = mem_ret.mem_wmask;
    assign retire.mem_rdata = mem_ret.mem_rmask != '0 ? dmem_rsp.rd_data : '0;
    assign retire.mem_wdata = mem_ret.mem_wdata;

    assign dbg_rsp.halt_pc   = halt_pc;
    assign dbg_rsp.reg_rdata = dbg_reg_rdata;

endmodule

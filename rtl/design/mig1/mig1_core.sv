/* Mig1 core: RISC-V RV32IM with Zicsr and Zicntr, synthesizable; the memories are outside.
 *
 * Instruction fetch and data access have 1 clock read latency, like SimROM,
 * SimRAM, SRAM and FPGA block RAM. Faults (ECALL, illegal instruction, misaligned
 * jump target or load/store address, ...) trap to mtvec in machine mode, MRET returns.
 * EBREAK traps too, or halts the core (halt=1) when the debugger sets
 * dbg_req.ebreak_halt; while halted, the debug port reads and writes registers, and
 * resume continues after EBREAK.
 *
 * Mig1Core only connects its parts:
 * - Mig1Fetch: PC, imem requests, the IF/ID register;
 * - Mig1Control: run, stall, redirect, traps, halt;
 * - Mig1Decode: the instruction taken apart, with the controls of every part;
 * - Mig1Regs: the register file, also for the debug port;
 * - Mig1Forward: results not yet in the register file, for ID;
 * - Mig1Pipe: the ID/EX and EX/MEM registers;
 * - Mig1Alu, Mig1Branch, Mig1Lsu (dmem requests), Mig1Csr, Mig1MulDiv: the parts of EX;
 * - Mig1LoadData: the loaded value, in MEM/WB.
 *
 * Pipeline IF | ID | EX | MEM/WB: IF fetches; ID decodes the instruction that arrives
 * from imem and reads its registers; EX executes: branches, traps, CSRs and stores
 * happen there, loads send their read; MEM/WB gets load data, writes rd and retires.
 * An instruction that leaves EX always completes. Signals of a stage have its prefix:
 * if_, id_, ex_, mem_.
 * A taken branch or jump, a trap and MRET cost two bubbles: the instructions in ID and
 * IF are dropped. Results are forwarded to ID (Mig1Forward); an instruction that reads
 * the rd of a load right before it waits one cycle in ID (load-use).
 * A division stays 34 cycles in EX.
 *
 * Mig1Cpu instantiates it, with simulation memories; synthesis (make mig1_synth) takes
 * Mig1Core as its top.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module Mig1Core import Mig1Pkg::*; #(
    parameter mig1_cfg_t CFG = MIG1_CFG    // configuration, see Mig1ConfigPkg
)(
    input  wire       clk,
    input  wire       rst_n,               // synchronous reset, active low

    // Memories: requests out, read data back 1 clock later.
    output imem_req_t imem_req,
    input  imem_rsp_t imem_rsp,
    output dmem_req_t dmem_req,
    input  dmem_rsp_t dmem_rsp,

    // Retire trace and halt.
    output wire       halt,                // core halted at EBREAK, see dbg_req.ebreak_halt
    output retire_t   retire,              // RVFI trace, see Mig1Pkg

    // Debug, used while halted.
    input  dbg_req_t  dbg_req,
    output dbg_rsp_t  dbg_rsp
);
    // IF and control
    fetch_ctrl_t  if_ctrl;          // Control -> Fetch
    pipe_ctrl_t   pipe_ctrl;        // Control -> Pipe
    csr_t         csr;              // mtvec, mepc: where traps and MRET go (no stage)

    // ID
    fetch_t       id_fetch;         // instruction in ID: valid, pc; arrives from imem
    insn_t        id_insn;
    decoded_t     id_dec;           // instruction in ID taken apart
    word_t        id_rf_rs1_data;   // register file values; id_rs1_data has forwarding
    word_t        id_rf_rs2_data;
    word_t        id_rs1_data;
    word_t        id_rs2_data;
    id_ex_t       id_ex_d;
    id_ex_t       id_ex_q;

    // EX
    fetch_t       ex_fetch;         // instruction in EX: valid, pc
    insn_t        ex_insn;
    decoded_t     ex_dec;           // instruction in EX taken apart
    word_t        ex_rs1_data;
    word_t        ex_rs2_data;
    word_t        ex_alu_result;    // also the load/store address rs1 + imm
    branch_t      ex_branch;        // taken, target, misaligned, from Mig1Branch
    word_t        ex_link;          // pc + 4 for JAL, JALR
    logic         ex_lsu_misaligned;
    lsu_mem_t     ex_lsu_mem;       // memory access, for retire
    byte_offset_t ex_load_offset;   // byte of the load address in the word
    word_t        ex_csr_rdata;     // old value of the CSR of a CSR instruction
    logic         ex_csr_illegal;
    word_t        ex_muldiv_result; // product, quotient or remainder of an M instruction
    logic         ex_muldiv_stall;
    logic         ex_done;          // instruction in EX completes: CSR write and minstret
                                    // now, rd and retire in MEM/WB
    trap_t        ex_trap;          // instruction in EX faults: retires as a trap
    logic         ex_rd_write;      // instruction in EX will write rd (not x0)
    reg_id_t      ex_rd;            // rd written by the instruction in EX, 0 when none
    word_t        ex_rd_data;       // rd value in EX: forwarding and the retire entry
    word_t        ex_next_pc;       // byte address of the next instruction, for retire
    retire_t      ex_retire;        // RVFI entry built in EX, completed in MEM/WB
    ex_mem_t      ex_mem_d;
    ex_mem_t      ex_mem_q;

    // MEM/WB
    retire_t      mem_ret;          // instruction in MEM/WB: its entry from EX
    word_t        mem_load_data;
    reg_id_t      mem_rd;           // rd written in MEM/WB, 0 when none
    logic         mem_rd_write;
    word_t        mem_rd_data;      // rd value written in MEM/WB: load data or EX's value
    logic [63:0]  retire_order;     // number of instructions retired so far

    // Debug
    iaddr_t       halt_pc;          // address of the EBREAK that halted the core
    word_t        dbg_reg_rdata;

    // IF
    Mig1Fetch #(.CFG(CFG)) u_mig1_fetch(
        .clk, .rst_n, .ctrl(if_ctrl), .imem_req, .fetch(id_fetch));

    Mig1Control u_mig1_control(
        .clk, .rst_n, .id_valid(id_fetch.valid), .id_dec, .ex_fetch, .ex_insn, .ex_dec,
        .ex_addr(ex_alu_result), .ex_branch, .ex_lsu_misaligned, .ex_csr_illegal,
        .ex_muldiv_stall, .csr, .ebreak_halt(dbg_req.ebreak_halt),
        .resume(dbg_req.resume), .fetch_ctrl(if_ctrl), .pipe_ctrl, .ex_done, .ex_trap,
        .halt, .halt_pc);

    // ID
    assign id_insn = imem_rsp.data;

    Mig1Decode u_mig1_decode(.insn(id_insn), .dec(id_dec));

    Mig1Regs u_mig1_regs(
        .clk, .halt,
        .rs1(id_dec.rs1), .rs2(id_dec.rs2), .rs1_data(id_rf_rs1_data), .rs2_data(id_rf_rs2_data),
        .rd_we(mem_rd_write), .rd(mem_rd), .rd_data(mem_rd_data),
        .dbg_reg_id(dbg_req.reg_id), .dbg_reg_wr(dbg_req.reg_wr),
        .dbg_reg_wdata(dbg_req.reg_wdata), .dbg_reg_rdata);

    Mig1Forward u_mig1_forward(
        .rs1(id_dec.rs1), .rs2(id_dec.rs2), .rf_rs1_data(id_rf_rs1_data),
        .rf_rs2_data(id_rf_rs2_data), .ex_rd, .ex_rd_data, .mem_rd, .mem_rd_data,
        .rs1_data(id_rs1_data), .rs2_data(id_rs2_data));

    assign id_ex_d = '{valid:    id_fetch.valid,
                       pc:       id_fetch.pc,
                       insn:     id_insn,
                       dec:      id_dec,
                       rs1_data: id_rs1_data,
                       rs2_data: id_rs2_data};

    Mig1Pipe u_mig1_pipe(.clk, .rst_n, .ctrl(pipe_ctrl), .id_ex_d, .id_ex_q, .ex_mem_d, .ex_mem_q);

    // EX
    assign ex_fetch       = '{valid: id_ex_q.valid, pc: id_ex_q.pc};
    assign ex_insn        = id_ex_q.insn;
    assign ex_dec         = id_ex_q.dec;
    assign ex_rs1_data    = id_ex_q.rs1_data;
    assign ex_rs2_data    = id_ex_q.rs2_data;

    Mig1Alu u_mig1_alu(
        .dec(ex_dec), .pc(ex_fetch.pc), .rs1_data(ex_rs1_data), .rs2_data(ex_rs2_data),
        .result(ex_alu_result));

    Mig1Branch u_mig1_branch(
        .dec(ex_dec), .pc(ex_fetch.pc), .rs1_data(ex_rs1_data), .rs2_data(ex_rs2_data),
        .branch(ex_branch), .link(ex_link));

    Mig1Lsu u_mig1_lsu(
        .valid(ex_fetch.valid), .dec(ex_dec), .addr(ex_alu_result), .rs2_data(ex_rs2_data),
        .dmem_req, .misaligned(ex_lsu_misaligned), .mem(ex_lsu_mem));

    assign ex_load_offset = ex_alu_result[DADDR_START-1:0];

    Mig1Csr u_mig1_csr(
        .clk, .rst_n, .valid(ex_fetch.valid), .done(ex_done), .dec(ex_dec),
        .rs1_data(ex_rs1_data), .pc(ex_fetch.pc), .trap(ex_trap), .rdata(ex_csr_rdata),
        .illegal(ex_csr_illegal), .csr);

    Mig1MulDiv u_mig1_muldiv(
        .clk, .rst_n, .valid(ex_fetch.valid), .dec(ex_dec), .rs1_data(ex_rs1_data),
        .rs2_data(ex_rs2_data), .stall(ex_muldiv_stall), .result(ex_muldiv_result));

    // rd value: decode tells whether rd is written and where its value comes from.
    assign ex_rd_write = ex_done && ex_dec.rd_we && ex_dec.rd != '0;
    assign ex_rd       = (ex_fetch.valid && ex_dec.rd_we) ? ex_dec.rd : '0;

    always_comb
        case (ex_dec.rd_src)
            RD_LINK:   ex_rd_data = ex_link;
            RD_CSR:    ex_rd_data = ex_csr_rdata;
            RD_MULDIV: ex_rd_data = ex_muldiv_result;
            default:   ex_rd_data = ex_alu_result;      // loads: MEM/WB replaces it
        endcase

    // Retire entry, RVFI: an instruction that completes or traps; fields it does not
    // use are 0. MEM/WB adds order, and the load data.
    assign ex_next_pc = if_ctrl.redirect ? {if_ctrl.target, {IADDR_START{1'b0}}} : ex_link;
    assign ex_retire  = '{valid:     ex_done || ex_trap.valid,
                          order:     '0,
                          insn:      ex_insn,
                          trap:      ex_trap.valid,
                          pc_rdata:  {ex_fetch.pc, {IADDR_START{1'b0}}},
                          pc_wdata:  ex_next_pc,
                          rs1_addr:  ex_dec.uses_rs1 ? ex_dec.rs1 : '0,
                          rs1_rdata: ex_dec.uses_rs1 ? ex_rs1_data : '0,
                          rs2_addr:  ex_dec.uses_rs2 ? ex_dec.rs2 : '0,
                          rs2_rdata: ex_dec.uses_rs2 ? ex_rs2_data : '0,
                          rd_addr:   ex_rd_write ? ex_dec.rd : '0,
                          rd_wdata:  ex_rd_write ? ex_rd_data : '0,
                          mem_addr:  ex_lsu_mem.addr,
                          mem_rmask: ex_lsu_mem.rmask,
                          mem_wmask: ex_lsu_mem.wmask,
                          mem_rdata: '0,
                          mem_wdata: ex_lsu_mem.wdata};

    assign ex_mem_d = '{valid:  ex_retire.valid,
                        ret:    ex_retire,
                        load:   ex_dec.rd_src == RD_LOAD,
                        funct3: ex_dec.funct3,
                        offset: ex_load_offset};

    // MEM/WB
    assign mem_ret = ex_mem_q.ret;

    Mig1LoadData u_mig1_load_data(
        .funct3(ex_mem_q.funct3), .offset(ex_mem_q.offset), .word(dmem_rsp.rd_data),
        .load_data(mem_load_data));

    // Write back: rd_addr of the entry is 0 when nothing is written (RVFI: traps, x0;
    // EX builds it from ex_done). A bubble keeps old fields (Mig1PipeReg clears only
    // valid, also at reset), so valid gates the write.
    assign mem_rd       = ex_mem_q.valid ? mem_ret.rd_addr : '0;
    assign mem_rd_write = mem_rd != '0;
    assign mem_rd_data  = ex_mem_q.load ? mem_load_data : mem_ret.rd_wdata;

    // Retire, RVFI: the entry from EX, with what MEM/WB adds.
    always_ff @(posedge clk)
        if (!rst_n)            retire_order <= '0;
        else if (retire.valid) retire_order <= retire_order + 1'b1;

    always_comb begin
        retire           = mem_ret;
        retire.valid     = ex_mem_q.valid;
        retire.order     = retire_order;
        retire.rd_wdata  = mem_rd_write ? mem_rd_data : '0;
        retire.mem_rdata = mem_ret.mem_rmask != '0 ? dmem_rsp.rd_data : '0;
    end

    assign dbg_rsp.halt_pc   = halt_pc;
    assign dbg_rsp.reg_rdata = dbg_reg_rdata;

endmodule

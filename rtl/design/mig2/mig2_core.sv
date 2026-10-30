/* Mig2 core: RISC-V RV32IM with Zicsr and Zicntr, synthesizable; the memories are outside.
 *
 * Instruction fetch and data access are valid/ready channels with the answers of reads
 * after them (imem_req_t, Mig2Pkg). Fetch waits for imem (Mig2Fetch); for dmem the core
 * still needs every request taken at once and its answer 1 clock later (a memory like SRAM
 * or FPGA block RAM; SimLatencyRAM with latency 1), and asserts it.
 * Faults (ECALL, illegal instruction, misaligned
 * jump target or load/store address, ...) trap to mtvec in machine mode, MRET returns.
 * EBREAK traps too, or halts the core (halt=1) when the debugger sets
 * dbg_req.ebreak_halt; while halted, the debug port reads and writes registers, and
 * resume continues after EBREAK.
 *
 * Mig2Core only connects its parts:
 * - Mig2Fetch: PC, imem requests, the IF/ID register;
 * - Mig2Control: run, stall, redirect, traps, halt;
 * - Mig2Decode: the instruction taken apart, with the controls of every part;
 * - Mig2Regs: the register file, also for the debug port;
 * - Mig2Forward: results not yet in the register file, for ID;
 * - Mig2Pipe: the ID/EX and EX/MEM registers;
 * - Mig2Alu, Mig2Branch, Mig2Lsu (dmem requests), Mig2Csr, Mig2MulDiv and the library
 *   block ComputeCoreBitmanip (Zbb with one operand): the parts of EX;
 * - Mig2LoadData: the loaded value, in MEM/WB.
 *
 * Pipeline IF | ID | EX | MEM/WB: IF fetches; ID decodes the instruction that arrives
 * from imem and reads its registers; EX executes: branches, traps, CSRs and stores
 * happen there, loads send their read; MEM/WB gets load data, writes rd and retires.
 * An instruction that leaves EX always completes. Signals of a stage have its prefix:
 * if_, id_, ex_, mem_.
 * A branch guessed wrong, JALR, a trap and MRET cost two bubbles: the instructions in ID
 * and IF are dropped; JAL and a branch guessed taken (Mig2BranchPredict) cost one: ID
 * redirects fetch to the target; none when the BTB of Mig2Fetch has them and sends fetch
 * to the target in IF already. A return costs one when the return-address stack
 * (ReturnAddressStack) predicts it. Results are forwarded to ID (Mig2Forward); an
 * instruction that reads
 * the rd of a load right before it waits one cycle in ID (load-use).
 * A division stays 34 cycles in EX.
 * Every slot without an instruction carries its reason (bubble_e); retire reports it
 * (retire.bubble), so each cycle retires an instruction or a bubble.
 *
 * Mig2Cpu instantiates it, with simulation memories; synthesis (make mig2_synth) takes
 * Mig2Core as its top.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "dark_circuit_assert.svh"

module Mig2Core import Mig2Pkg::*; #(
    parameter mig2_cfg_t CFG = MIG2_CFG    // configuration, see Mig2ConfigPkg
)(
    input  wire         clk,
    input  wire         rst_n,             // synchronous reset, active low

    // Memories: requests out, read data back 1 clock later.
    output imem_req_t   imem_req,
    input  imem_rsp_t   imem_rsp,
    output dmem_req_t   dmem_req,
    input  dmem_rsp_t   dmem_rsp,

    // Retire trace, pipeline view and halt.
    output wire         halt,              // core halted at EBREAK, see dbg_req.ebreak_halt
    output retire_t     retire,            // RVFI trace, see Mig2Pkg
    output pipe_trace_t pipe_trace,        // pipeline view for testbenches, see Mig2Pkg

    // Debug, used while halted.
    input  dbg_req_t    dbg_req,
    output dbg_rsp_t    dbg_rsp
);
    // IF and control
    fetch_ctrl_t  if_ctrl;          // Control -> Fetch
    pipe_ctrl_t   pipe_ctrl;        // Control -> Pipe
    csr_t         csr;              // mtvec, mepc: where traps and MRET go (no stage)

    // ID
    fetch_t       id_fetch;         // instruction in ID: valid, pc; arrives from imem
    btb_pred_t    id_btb;           // what the BTB said in IF for the instruction in ID
    btb_update_t  btb_update;       // Control -> Fetch: a branch or JAL completed in EX
    btb_inval_t   btb_inval;        // Control -> Fetch: the BTB was wrong for the insn in ID
    ras_ctrl_t    ras_ctrl;         // Control -> return stack: push for a call, pop for a return
    iaddr_t       id_ras_top;       // top of the return stack: where a return in ID goes
    insn_t        id_insn;          // instruction in ID: its word, from Mig2Fetch
    logic         id_wait;          // the slot in ID waits for its word from imem
    logic         id_keep;          // IF/ID keeps its slot
    decoded_t     id_dec;           // instruction in ID taken apart
    logic         id_pred_taken;    // conditional branch in ID guessed taken
    logic         id_redirected;    // fetch went to the target of the insn in ID (IF or ID)
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
    branch_t      ex_branch;        // taken, target, misaligned, from Mig2Branch
    word_t        ex_link;          // pc + 4 for JAL, JALR
    logic         ex_lsu_misaligned;
    lsu_mem_t     ex_lsu_mem;       // memory access, for retire
    byte_offset_t ex_load_offset;   // byte of the load address in the word
    word_t        ex_csr_rdata;     // old value of the CSR of a CSR instruction
    logic         ex_csr_illegal;
    word_t        ex_muldiv_result; // product, quotient or remainder of an M instruction
    logic         ex_muldiv_stall;
    word_t        ex_bitmanip_result;   // Zbb with one operand (ComputeCoreBitmanip)
    logic         ex_done;          // instruction in EX completes: CSR write and minstret
                                    // now, rd and retire in MEM/WB
    trap_t        ex_trap;          // instruction in EX faults: retires as a trap
    logic         ex_rd_write;      // instruction in EX will write rd (not x0)
    reg_id_t      ex_rd;            // rd written by the instruction in EX, 0 when none
    word_t        ex_rd_data;       // rd value in EX: forwarding and the retire entry
    iaddr_t       ex_next_pc;       // next instruction, for retire (Mig2Control)
    retire_t      ex_retire;        // RVFI entry built in EX, completed in MEM/WB
    bubble_e      ex_bubble;        // nothing completes or traps in EX: why
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
    Mig2Fetch #(.CFG(CFG)) u_mig2_fetch(
        .clk, .rst_n, .ctrl(if_ctrl), .btb_update, .btb_inval, .imem_req, .imem_rsp,
        .fetch(id_fetch), .insn(id_insn), .btb_pred(id_btb), .id_wait, .id_keep);

    Mig2Control u_mig2_control(
        .clk, .rst_n, .if_pc(imem_req.addr), .id_fetch, .id_dec, .id_pred_taken, .id_btb,
        .id_ras_top, .ex_ras_target(id_ex_q.ras_target),
        .ex_fetch, .ex_insn, .ex_dec, .ex_redirected(id_ex_q.redirected),
        .ex_btb(id_ex_q.btb), .ex_addr(ex_alu_result), .ex_branch, .ex_lsu_misaligned,
        .ex_csr_illegal, .ex_muldiv_stall, .csr, .ebreak_halt(dbg_req.ebreak_halt),
        .resume(dbg_req.resume), .fetch_ctrl(if_ctrl), .pipe_ctrl, .btb_update, .btb_inval,
        .ras_ctrl,
        .id_redirected, .ex_done, .ex_trap, .ex_next_pc, .halt, .halt_pc);

    Mig2Decode u_mig2_decode(.insn(id_insn), .dec(id_dec));

    Mig2BranchPredict u_mig2_branch_predict(.dec(id_dec), .taken(id_pred_taken));

    // Return-address stack: Control pushes the calls and pops the returns that leave ID.
    // @kb: rtl/design/mig2/control_blocks_outside
    ReturnAddressStack #(.ADDR_WIDTH(CFG.ras_addr_width), .DATA_WIDTH($bits(iaddr_t)))
        u_return_address_stack(.clk, .rst_n, .push(ras_ctrl.push),
                               .push_addr(ras_ctrl.push_addr), .pop(ras_ctrl.pop),
                               .top_addr(id_ras_top));

    Mig2Regs u_mig2_regs(
        .clk, .halt,
        .rs1(id_dec.rs1), .rs2(id_dec.rs2), .rs1_data(id_rf_rs1_data), .rs2_data(id_rf_rs2_data),
        .rd_we(mem_rd_write), .rd(mem_rd), .rd_data(mem_rd_data),
        .dbg_reg_id(dbg_req.reg_id), .dbg_reg_wr(dbg_req.reg_wr),
        .dbg_reg_wdata(dbg_req.reg_wdata), .dbg_reg_rdata);

    Mig2Forward u_mig2_forward(
        .rs1(id_dec.rs1), .rs2(id_dec.rs2), .rf_rs1_data(id_rf_rs1_data),
        .rf_rs2_data(id_rf_rs2_data), .ex_rd, .ex_rd_data, .mem_rd, .mem_rd_data,
        .rs1_data(id_rs1_data), .rs2_data(id_rs2_data));

    assign id_ex_d = '{valid:      id_fetch.valid,
                       bubble:     id_fetch.bubble,
                       pc:         id_fetch.pc,
                       insn:       id_insn,
                       dec:        id_dec,
                       redirected: id_redirected,
                       btb:        id_btb,
                       ras_target: id_ras_top,
                       rs1_data:   id_rs1_data,
                       rs2_data:   id_rs2_data};

    Mig2Pipe u_mig2_pipe(.clk, .rst_n, .ctrl(pipe_ctrl), .id_ex_d, .id_ex_q, .ex_mem_d, .ex_mem_q);

    // EX
    assign ex_fetch       = '{valid: id_ex_q.valid, bubble: id_ex_q.bubble, pc: id_ex_q.pc};
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
        .valid(ex_fetch.valid), .dec(ex_dec), .rs1_data(ex_rs1_data), .addr(ex_alu_result),
        .rs2_data(ex_rs2_data), .dmem_req, .misaligned(ex_lsu_misaligned), .mem(ex_lsu_mem));

    // Mig2Lsu adds the byte offset of its own; it is the low bits of the ALU's address.
    `DC_ASSERT(a_lsu_offset, !(ex_fetch.valid && (ex_dec.mem.read || ex_dec.mem.write)) ||
               byte_offset_t'(ex_rs1_data[DADDR_START-1:0] + ex_dec.imm[DADDR_START-1:0]) ==
               ex_alu_result[DADDR_START-1:0])

    assign ex_load_offset = ex_alu_result[DADDR_START-1:0];

    Mig2Csr u_mig2_csr(
        .clk, .rst_n, .valid(ex_fetch.valid), .done(ex_done), .dec(ex_dec),
        .rs1_data(ex_rs1_data), .pc(ex_fetch.pc), .trap(ex_trap), .rdata(ex_csr_rdata),
        .illegal(ex_csr_illegal), .csr);

    Mig2MulDiv u_mig2_muldiv(
        .clk, .rst_n, .valid(ex_fetch.valid), .dec(ex_dec), .rs1_data(ex_rs1_data),
        .rs2_data(ex_rs2_data), .stall(ex_muldiv_stall), .result(ex_muldiv_result));

    ComputeCoreBitmanip #(.WIDTH(WIDTH)) u_compute_core_bitmanip(
        .in(ex_rs1_data), .op(ex_dec.bitmanip), .out(ex_bitmanip_result));

    // rd value: decode tells whether rd is written and where its value comes from.
    assign ex_rd_write = ex_done && ex_dec.rd_we && ex_dec.rd != '0;
    assign ex_rd       = (ex_fetch.valid && ex_dec.rd_we) ? ex_dec.rd : '0;

    always_comb
        case (ex_dec.rd_src)
            RD_LINK:     ex_rd_data = ex_link;
            RD_CSR:      ex_rd_data = ex_csr_rdata;
            RD_MULDIV:   ex_rd_data = ex_muldiv_result;
            RD_BITMANIP: ex_rd_data = ex_bitmanip_result;
            default:     ex_rd_data = ex_alu_result;    // loads: MEM/WB replaces it
        endcase

    // Retire entry, RVFI: an instruction that completes or traps; fields it does not
    // use are 0. MEM/WB adds order, bubble and the load data.
    assign ex_retire  = '{valid:     ex_done || ex_trap.valid,
                          bubble:    BUBBLE_NONE,
                          order:     '0,
                          insn:      ex_insn,
                          trap:      ex_trap.valid,
                          pc_rdata:  {ex_fetch.pc, {IADDR_START{1'b0}}},
                          pc_wdata:  {ex_next_pc, {IADDR_START{1'b0}}},
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

    // Bubble of EX/MEM: EX holds a bubble, which moves on with its reason, or EX waits for
    // a division (the only way an instruction in EX neither completes nor traps).
    assign ex_bubble = ex_retire.valid ? BUBBLE_NONE :
                       !ex_fetch.valid ? ex_fetch.bubble : BUBBLE_DIV;

    `DC_ASSERT(a_ex_bubble_div, ex_retire.valid || !ex_fetch.valid || ex_muldiv_stall)

    assign ex_mem_d = '{valid:  ex_retire.valid,
                        bubble: ex_bubble,
                        ret:    ex_retire,
                        load:   ex_dec.rd_src == RD_LOAD,
                        funct3: ex_dec.funct3,
                        offset: ex_load_offset};

    // MEM/WB
    assign mem_ret = ex_mem_q.ret;

    Mig2LoadData u_mig2_load_data(
        .funct3(ex_mem_q.funct3), .offset(ex_mem_q.offset), .word(dmem_rsp.data),
        .load_data(mem_load_data));

    // Write back: rd_addr of the entry is 0 when nothing is written (RVFI: traps, x0;
    // EX builds it from ex_done). A bubble keeps old fields (Mig2PipeReg clears only
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
        retire.bubble    = ex_mem_q.bubble;
        retire.order     = retire_order;
        retire.rd_wdata  = mem_rd_write ? mem_rd_data : '0;
        retire.mem_rdata = mem_ret.mem_rmask != '0 ? dmem_rsp.data : '0;
    end

    // Pipeline view: the slots of the stages and their moves (pipe_trace_t, Mig2Pkg).
    assign pipe_trace = '{if_req:   imem_req.valid && imem_rsp.ready,
                          if_pc:    imem_req.addr,
                          id:       '{valid:  id_fetch.valid || id_wait,
                                      bubble: id_fetch.bubble,
                                      pc:     id_fetch.pc},
                          ex:       ex_fetch,
                          mem:      '{valid:  ex_mem_q.valid,
                                      bubble: ex_mem_q.bubble,
                                      pc:     mem_ret.pc_rdata[WIDTH-1:IADDR_START]},
                          redirect: if_ctrl.redirect,
                          id_wait:  id_wait,
                          id_stall: id_keep,
                          ex_stall: pipe_ctrl.ex_stall,
                          ex_flush: pipe_ctrl.ex_flush};

    assign dbg_rsp.halt_pc   = halt_pc;
    assign dbg_rsp.reg_rdata = dbg_reg_rdata;

    // dmem latency 1 for now: every request is taken at once and a read is answered in the
    // next clock, and only then (MEM/WB does not wait for memory yet).
    `DC_ASSERT(a_dmem_ready, !dmem_req.valid || dmem_rsp.ready)
    `DC_ASSERT_NEXT(a_dmem_on_time, dmem_req.valid && !dmem_req.we && dmem_rsp.ready,
                    dmem_rsp.valid)
    `DC_ASSERT_NEXT(a_dmem_no_extra, !(dmem_req.valid && !dmem_req.we && dmem_rsp.ready),
                    !dmem_rsp.valid)

endmodule

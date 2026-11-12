/* Mig3 core: RISC-V RV32IM with Zicsr and Zicntr, synthesizable, with an instruction and a
 * data cache that share one memory port; the memory is outside.
 *
 * Instruction fetch and data access are valid/ready channels with the answers of reads
 * after them (imem_req_t, dmem_req_t, Mig3Pkg), to the caches (Mig3Caches), and from them to
 * the one memory port (mem_req_t, cache lines). Fetch waits for the I-cache (Mig3Fetch); a
 * load or store waits in EX until the D-cache takes its request, a load waits in MEM/WB for
 * its word (one data request in flight). uncached=1 makes every request bypass the caches
 * (tests that count cycles).
 * Faults (ECALL, illegal instruction, misaligned
 * jump target or load/store address, ...) trap to mtvec in machine mode, MRET returns.
 * EBREAK traps too, or halts the core (halt=1) when the debugger sets
 * dbg_req.ebreak_halt; while halted, the debug port reads and writes registers, and
 * resume continues after EBREAK.
 *
 * Mig3Core only connects its parts:
 * - Mig3Caches: the I-cache and the D-cache, between the pipeline and the memory port;
 * - Mig3Fetch: PC, I-cache requests, the stages IF2 and the register into ID;
 * - Mig3Control: run, stall, redirect, traps, halt;
 * - Mig3Decode: the instruction taken apart, with the controls of every part;
 * - Mig3Regs: the register file, also for the debug port;
 * - Mig3Forward: results not yet in the register file, for ID;
 * - Mig3Pipe: the ID/EX and EX/MEM registers;
 * - Mig3Alu, Mig3Branch, Mig3Lsu (D-cache requests), Mig3Atomic (the reservation of LR/SC),
 *   Mig3Csr, Mig3MulDiv, Mig3Fpu (F on the x registers: Zfinx), Mig3Packed (packed SIMD:
 *   P) and the library block ComputeCoreBitmanip (Zbb with one operand): the parts of EX;
 * - Mig3LoadData: the loaded value, in MEM/WB.
 *
 * Pipeline IF | ID | EX | MEM/WB: IF fetches; ID decodes the instruction that arrives
 * from the I-cache and reads its registers; EX executes: branches, traps, CSRs and stores
 * happen there, loads send their read; MEM/WB gets load data, writes rd and retires.
 * An instruction that leaves EX always completes (a load when its word comes). Signals of
 * a stage have its prefix:
 * if_, id_, ex_, mem_.
 * A branch guessed wrong, JALR, a trap and MRET cost two bubbles: the instructions in ID
 * and IF are dropped; JAL and a branch guessed taken (Mig3BranchPredict) cost one: ID
 * redirects fetch to the target; none when the BTB of Mig3Fetch has them and sends fetch
 * to the target in IF already. A return costs one when the return-address stack
 * (ReturnAddressStack) predicts it. Results are forwarded to ID (Mig3Forward); an
 * instruction that reads
 * the rd of a load right before it waits one cycle in ID (load-use).
 * A division stays 34 cycles in EX, an F instruction 2 to 27 (Mig3Fpu); an R4 one
 * (FMADD.S ...) reads rs3 in its first cycle in EX through ID's rs2 port, lent to it:
 * the instruction in ID waits behind it then anyway.
 * Every slot without an instruction carries its reason (bubble_e); retire reports it
 * (retire.bubble), so each cycle retires an instruction or a bubble.
 *
 * Mig3Cpu instantiates it, with a simulation memory; synthesis (make mig3_synth) takes
 * Mig3Core as its top.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "dark_circuit_assert.svh"

module Mig3Core import Mig3Pkg::*; #(
    parameter mig3_cfg_t CFG = MIG3_CFG    // configuration, see Mig3ConfigPkg
)(
    input  wire         clk,
    input  wire         rst_n,             // synchronous reset, active low

    // Memory, code and data, behind the caches: requests out, answers of reads back later.
    output mem_req_t    mem_req,
    input  mem_rsp_t    mem_rsp,
    input  wire         uncached,          // every request bypasses the caches (Mig3Caches)
    input  wire         meip,              // machine external interrupt (a PLIC, Mig3Cpu)

    // Retire trace, pipeline view and halt.
    output wire         halt,              // core halted at EBREAK, see dbg_req.ebreak_halt
    output retire_t     retire,            // RVFI trace, see Mig3Pkg
    output pipe_trace_t pipe_trace,        // pipeline view for testbenches, see Mig3Pkg

    // Debug, used while halted.
    input  dbg_req_t    dbg_req,
    output dbg_rsp_t    dbg_rsp
);
    // The pipeline's channels to the caches
    imem_req_t    icache_req;       // Fetch -> I-cache
    imem_rsp_t    icache_rsp;
    dmem_req_t    dcache_req;       // Lsu -> D-cache
    dmem_rsp_t    dcache_rsp;

    // IF and control
    fetch_ctrl_t  if_ctrl;          // Control -> Fetch
    pipe_ctrl_t   pipe_ctrl;        // Control -> Pipe
    csr_t         csr;              // mtvec, mepc: where traps and MRET go (no stage)

    // ID
    fetch_t       id_fetch;         // instruction in ID: valid, pc; from IF2, a register
    btb_pred_t    id_btb;           // what the BTB said in IF for the instruction in ID
    btb_update_t  btb_update;       // Control -> Fetch: a branch or JAL completed in EX
    btb_inval_t   btb_inval;        // Control -> Fetch: the BTB was wrong for the insn in ID
    ras_ctrl_t    ras_ctrl;         // Control -> return stack: push for a call, pop for a return
    iaddr_t       id_ras_top;       // top of the return stack: where a return in ID goes
    insn_t        id_insn;          // instruction in ID: its word, from Mig3Fetch
    iaddr_t       id_next_pc;       // the address fetch requested after the insn in ID
    fetch_t       if2_slot;         // the slot of IF2 (pipeline view)
    logic         if2_wait;         // the slot in IF2 waits for its word from the I-cache
    logic         if2_keep;         // IF2 keeps its slot
    logic         if_taken;         // an instruction enters IF2 (pipeline view)
    decoded_t     id_dec;           // instruction in ID taken apart
    logic         id_pred_taken;    // conditional branch in ID guessed taken
    logic         id_redirected;    // fetch went to the target of the insn in ID (IF or ID)
    word_t        id_rf_rs1_data;   // register file values; id_rs1_data has forwarding
    word_t        id_rf_rs2_data;
    word_t        id_rs1_data;
    word_t        id_rs2_data;
    reg_id_t      id_rf_rs2;        // the register rs2's port reads: rs3 for EX's R4
    reg_id_t      id_fwd_ex_rd;     // ex_rd for forwarding: none while the port is lent
    id_ex_t       id_ex_d;
    id_ex_t       id_ex_q;

    // EX
    fetch_t       ex_fetch;         // instruction in EX: valid, pc
    insn_t        ex_insn;
    decoded_t     ex_dec;           // instruction in EX taken apart
    word_t        ex_rs1_data;
    word_t        ex_rs2_data;
    word_t        ex_alu_result;    // also the load/store address rs1 + imm
    branch_t      ex_branch;        // taken, target, misaligned, from Mig3Branch
    word_t        ex_link;          // pc + 4 for JAL, JALR
    logic         ex_lsu_misaligned;
    lsu_mem_t     ex_lsu_mem;       // memory access, for retire
    byte_offset_t ex_load_offset;   // byte of the load address in the word
    word_t        ex_csr_rdata;     // old value of the CSR of a CSR instruction
    logic         ex_csr_illegal;
    word_t        ex_muldiv_result; // product, quotient or remainder of an M instruction
    logic         ex_muldiv_stall;
    word_t        ex_fpu_result;    // result of an F instruction (Zfinx)
    FpPkg::flags_t ex_fpu_flags;    // its flags, for fflags
    logic         ex_fpu_stall;
    logic         ex_fpu_illegal;   // the F instruction can not be done: it traps
    logic         ex_fpu_rs3_read;  // the R4 in EX wants rs3 (not valid-gated)
    logic         ex_rs3_read;      // ... and is there: ID's rs2 port is lent to it
    RiscvPkg::funct3_t ex_frm;      // fcsr.frm: the FPU's mode for FRM_DYN
    logic         ex_lsu_valid;     // the load or store in EX may send its request
    logic         ex_dmem_wait;     // the D-cache does not take the request of EX
    logic         ex_sc_cancel;     // the SC in EX fails: no store (Mig3Atomic)
    word_t        ex_atomic_rd_data; // SC: 0 stored, 1 failed
    word_t        ex_bitmanip_result;   // Zbb with one operand (ComputeCoreBitmanip)
    word_t        ex_packed_result;     // packed SIMD (Mig3Packed)
    logic         ex_done;          // instruction in EX completes: CSR write and minstret
                                    // now, rd and retire in MEM/WB
    trap_t        ex_trap;          // instruction in EX faults: retires as a trap
    logic         ex_irq;           // an interrupt is taken on it: it does nothing
    logic         ex_wfi_wait;      // WFI in EX waits for an interrupt
    logic         ex_rd_write;      // instruction in EX will write rd (not x0)
    reg_id_t      ex_rd;            // rd written by the instruction in EX, 0 when none
    word_t        ex_rd_data;       // rd value in EX: forwarding and the retire entry
    word_t        ex_rd_wdata;      // rd value of the retire entry: also an SC's result
    iaddr_t       ex_next_pc;       // next instruction, for retire (Mig3Control)
    retire_t      ex_retire;        // RVFI entry built in EX, completed in MEM/WB
    bubble_e      ex_bubble;        // nothing completes or traps in EX: why
    ex_mem_t      ex_mem_d;
    ex_mem_t      ex_mem_q;

    // MEM/WB
    retire_t      mem_ret;          // instruction in MEM/WB: its entry from EX
    word_t        mem_load_data;
    logic         mem_wait;         // the load in MEM/WB waits for its word from the D-cache
    reg_id_t      mem_rd;           // rd written in MEM/WB, 0 when none
    logic         mem_rd_write;
    word_t        mem_rd_data;      // rd value written in MEM/WB: load data or EX's value
    logic [63:0]  retire_order;     // number of instructions retired so far

    // Debug
    iaddr_t       halt_pc;          // address of the EBREAK that halted the core
    word_t        dbg_reg_rdata;

    // Caches, between the pipeline and the memory port. When fetch and data want memory
    // together, the instruction side goes first while ID has no instruction (after a
    // redirect, or while fetch waits): then every stage starves; else data first.
    // @kb: rtl/design/mig2/caches_in_core
    // @kb: rtl/design/mig2/single_memory
    logic [1:0] mem_prio;             // the arbiter's tie
    assign mem_prio = id_fetch.valid ? CachePkg::PRIO_NONE : CachePkg::PRIO_INSN;
    Mig3Caches #(.CFG(CFG)) u_caches(
        .clk, .rst_n, .uncached, .prio(mem_prio), .icache_req, .icache_rsp, .dcache_req,
        .dcache_rsp, .mem_req, .mem_rsp);

    // IF
    Mig3Fetch #(.CFG(CFG)) u_mig3_fetch(
        .clk, .rst_n, .uncached, .ctrl(if_ctrl), .btb_update, .btb_inval,
        .imem_req(icache_req), .imem_rsp(icache_rsp), .fetch(id_fetch), .insn(id_insn),
        .btb_pred(id_btb), .id_next_pc, .if_taken, .if2(if2_slot), .if2_wait, .if2_keep);

    Mig3Control u_mig3_control(
        .clk, .rst_n, .id_next_pc, .id_fetch, .id_dec, .id_pred_taken, .id_btb,
        .id_ras_top, .ex_ras_target(id_ex_q.ras_target),
        .ex_fetch, .ex_insn, .ex_dec, .ex_redirected(id_ex_q.redirected),
        .ex_btb(id_ex_q.btb), .ex_addr(ex_alu_result), .ex_branch, .ex_lsu_misaligned,
        .ex_csr_illegal, .ex_muldiv_stall, .ex_fpu_stall, .ex_fpu_illegal, .ex_dmem_wait,
        .mem_wait, .csr,
        .ebreak_halt(dbg_req.ebreak_halt),
        .resume(dbg_req.resume), .fetch_ctrl(if_ctrl), .pipe_ctrl, .btb_update, .btb_inval,
        .ras_ctrl,
        .id_redirected, .ex_done, .ex_trap, .ex_irq, .ex_wfi_wait, .ex_next_pc, .halt,
        .halt_pc);

    Mig3Decode u_mig3_decode(.insn(id_insn), .dec(id_dec));

    Mig3BranchPredict u_mig3_branch_predict(.dec(id_dec), .taken(id_pred_taken));

    // Return-address stack: Control pushes the calls and pops the returns that leave ID.
    // @kb: rtl/design/mig2/control_blocks_outside
    ReturnAddressStack #(.ADDR_WIDTH(CFG.ras_addr_width), .DATA_WIDTH($bits(iaddr_t)))
        u_return_address_stack(.clk, .rst_n, .push(ras_ctrl.push),
                               .push_addr(ras_ctrl.push_addr), .pop(ras_ctrl.pop),
                               .top_addr(id_ras_top));

    // rs3 of the R4 instruction in EX, through ID's rs2 port in its first cycle there: ID
    // waits behind it (Mig3Fpu stalls EX) or is flushed by its trap, so ID's own rs2
    // read means nothing then. Forwarding from EX is off meanwhile (EX holds the R4
    // itself); rs3's newest writer is in MEM/WB. The select comes from flops.
    // @kb: rtl/design/mig3/rs3_read
    assign ex_rs3_read  = ex_fetch.valid && ex_fpu_rs3_read;
    assign id_rf_rs2    = ex_rs3_read ? ex_dec.rs3 : id_dec.rs2;
    assign id_fwd_ex_rd = ex_rs3_read ? '0 : ex_rd;

    Mig3Regs u_mig3_regs(
        .clk, .halt,
        .rs1(id_dec.rs1), .rs2(id_rf_rs2), .rs1_data(id_rf_rs1_data), .rs2_data(id_rf_rs2_data),
        .rd_we(mem_rd_write), .rd(mem_rd), .rd_data(mem_rd_data),
        .dbg_reg_id(dbg_req.reg_id), .dbg_reg_wr(dbg_req.reg_wr),
        .dbg_reg_wdata(dbg_req.reg_wdata), .dbg_reg_rdata);

    Mig3Forward u_mig3_forward(
        .rs1(id_dec.rs1), .rs2(id_rf_rs2), .rf_rs1_data(id_rf_rs1_data),
        .rf_rs2_data(id_rf_rs2_data), .ex_rd(id_fwd_ex_rd), .ex_rd_data, .mem_rd,
        .mem_rd_data,
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

    Mig3Pipe u_mig3_pipe(.clk, .rst_n, .ctrl(pipe_ctrl), .id_ex_d, .id_ex_q, .ex_mem_d, .ex_mem_q);

    // EX
    assign ex_fetch       = '{valid: id_ex_q.valid, bubble: id_ex_q.bubble, pc: id_ex_q.pc};
    assign ex_insn        = id_ex_q.insn;
    assign ex_dec         = id_ex_q.dec;
    assign ex_rs1_data    = id_ex_q.rs1_data;
    assign ex_rs2_data    = id_ex_q.rs2_data;

    Mig3Alu u_mig3_alu(
        .dec(ex_dec), .pc(ex_fetch.pc), .rs1_data(ex_rs1_data), .rs2_data(ex_rs2_data),
        .result(ex_alu_result));

    Mig3Branch u_mig3_branch(
        .dec(ex_dec), .pc(ex_fetch.pc), .rs1_data(ex_rs1_data), .rs2_data(ex_rs2_data),
        .branch(ex_branch), .link(ex_link));

    // One data request in flight: EX sends its request only while no load in MEM/WB waits
    // (or its word comes now); a request the D-cache does not take stays offered, EX waits.
    // An instruction an interrupt is taken on sends nothing.
    assign ex_lsu_valid = ex_fetch.valid && !mem_wait && !ex_irq;
    assign ex_dmem_wait = dcache_req.valid && !dcache_rsp.ready;

    Mig3Lsu u_mig3_lsu(
        .valid(ex_lsu_valid), .dec(ex_dec), .rs1_data(ex_rs1_data), .addr(ex_alu_result),
        .rs2_data(ex_rs2_data), .cancel(ex_sc_cancel), .dmem_req(dcache_req),
        .misaligned(ex_lsu_misaligned), .mem(ex_lsu_mem));

    // LR/SC: the reservation; a failing SC cancels its store in Mig3Lsu.
    // @kb: rtl/design/mig3/lr_sc
    Mig3Atomic u_atomic(
        .clk, .rst_n, .valid(ex_fetch.valid), .done(ex_done), .dec(ex_dec),
        .rs1_data(ex_rs1_data), .trap(ex_trap), .cancel(ex_sc_cancel),
        .rd_data(ex_atomic_rd_data));

    // An instruction an interrupt is taken on sends nothing to the D-cache.
    `DC_ASSERT(a_irq_no_request, !ex_irq || !dcache_req.valid)
    // A failing SC sends nothing to the D-cache.
    `DC_ASSERT(a_sc_cancel_no_req, !ex_sc_cancel || !dcache_req.valid)

    // Mig3Lsu adds the byte offset of its own; it is the low bits of the ALU's address.
    `DC_ASSERT(a_lsu_offset, !(ex_fetch.valid && (ex_dec.mem.read || ex_dec.mem.write)) ||
               byte_offset_t'(ex_rs1_data[DADDR_START-1:0] + ex_dec.imm[DADDR_START-1:0]) ==
               ex_alu_result[DADDR_START-1:0])

    assign ex_load_offset = ex_alu_result[DADDR_START-1:0];

    Mig3Csr u_mig3_csr(
        .clk, .rst_n, .valid(ex_fetch.valid), .done(ex_done), .dec(ex_dec),
        .rs1_data(ex_rs1_data), .pc(ex_fetch.pc), .meip, .trap(ex_trap), .rdata(ex_csr_rdata),
        .illegal(ex_csr_illegal), .csr, .fp_flags(ex_fpu_flags), .frm(ex_frm),
        .vxsat_set(1'b0));  // the packed unit (P): none yet, kb rtl/design/mig3/p_profile

    // A division starts in the first cycle the instruction acts, when Control takes
    // interrupts, as the FPU's operations (not behind a load in MEM/WB: an interrupt
    // taken after that wait would trap a division running).
    // @kb: rtl/design/mig3/interrupts
    Mig3MulDiv u_mig3_muldiv(
        .clk, .rst_n, .valid(ex_fetch.valid && !mem_wait && !ex_irq), .hold(mem_wait),
        .dec(ex_dec), .rs1_data(ex_rs1_data), .rs2_data(ex_rs2_data),
        .stall(ex_muldiv_stall), .result(ex_muldiv_result));

    // F on the x registers (Zfinx): a unit starts in the first cycle the instruction acts,
    // when Control takes interrupts: never one on an operation in flight.
    // @kb: rtl/design/mig3/fpu
    Mig3Fpu u_mig3_fpu(
        .clk, .rst_n, .valid(ex_fetch.valid && !mem_wait && !ex_irq), .hold(mem_wait),
        .dec(ex_dec), .rs1_data(ex_rs1_data), .rs2_data(ex_rs2_data),
        .rs3_data(id_rs2_data), .frm(ex_frm), .illegal(ex_fpu_illegal),
        .rs3_read(ex_fpu_rs3_read), .stall(ex_fpu_stall), .result(ex_fpu_result),
        .flags(ex_fpu_flags));

    // ID's instruction does not move while its rs2 port is lent to EX's R4.
    `DC_ASSERT(a_rs3_port_lent, !ex_rs3_read || pipe_ctrl.ex_stall || pipe_ctrl.ex_flush)

    ComputeCoreBitmanip #(.WIDTH(WIDTH)) u_compute_core_bitmanip(
        .in(ex_rs1_data), .op(ex_dec.bitmanip), .out(ex_bitmanip_result));

    Mig3Packed u_mig3_packed(
        .dec(ex_dec), .rs1_data(ex_rs1_data), .rs2_data(ex_rs2_data), .result(ex_packed_result));

    // rd value: decode tells whether rd is written and where its value comes from.
    assign ex_rd_write = ex_done && ex_dec.rd_we && ex_dec.rd != '0;
    assign ex_rd       = (ex_fetch.valid && ex_dec.rd_we) ? ex_dec.rd : '0;

    always_comb
        case (ex_dec.rd_src)
            RD_LINK:     ex_rd_data = ex_link;
            RD_CSR:      ex_rd_data = ex_csr_rdata;
            RD_MULDIV:   ex_rd_data = ex_muldiv_result;
            RD_FP:       ex_rd_data = ex_fpu_result;
            RD_BITMANIP: ex_rd_data = ex_bitmanip_result;
            RD_PACKED:   ex_rd_data = ex_packed_result;
            default:     ex_rd_data = ex_alu_result;    // loads: MEM/WB replaces it
        endcase

    // rd value of the retire entry: an SC's result goes to MEM/WB only, not into EX's
    // forwarding (ex_rd_data): the reservation compare stays off that path, and
    // Mig3Control holds an instruction that reads it, as after a load.
    // @kb: rtl/design/mig3/lr_sc
    assign ex_rd_wdata = ex_dec.rd_src == RD_ATOMIC ? ex_atomic_rd_data : ex_rd_data;

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
                          rd_wdata:  ex_rd_write ? ex_rd_wdata : '0,
                          mem_addr:  ex_lsu_mem.addr,
                          mem_rmask: ex_lsu_mem.rmask,
                          mem_wmask: ex_lsu_mem.wmask,
                          mem_rdata: '0,
                          mem_wdata: ex_lsu_mem.wdata};

    // Bubble of EX/MEM: EX holds a bubble, which moves on with its reason, or EX waits for
    // a division, an F instruction's result, an interrupt (WFI) or the D-cache to take its
    // request (EX/MEM keeps its load while it waits for its word: no bubble goes in then).
    assign ex_bubble = ex_retire.valid ? BUBBLE_NONE :
                       !ex_fetch.valid ? ex_fetch.bubble :
                       ex_muldiv_stall ? BUBBLE_DIV :
                       ex_fpu_stall    ? BUBBLE_FPU :
                       ex_wfi_wait     ? BUBBLE_WFI : BUBBLE_DMEM;

    `DC_ASSERT(a_ex_bubble_why, ex_retire.valid || !ex_fetch.valid || ex_muldiv_stall ||
                                ex_fpu_stall || ex_wfi_wait || ex_dmem_wait || mem_wait)

    // load: a load that sent its read (a misaligned one traps and reads nothing); MEM/WB
    // waits for its word.
    assign ex_mem_d = '{valid:  ex_retire.valid,
                        bubble: ex_bubble,
                        ret:    ex_retire,
                        load:   ex_dec.rd_src == RD_LOAD && !ex_trap.valid,
                        funct3: ex_dec.funct3,
                        offset: ex_load_offset};

    // MEM/WB
    assign mem_ret = ex_mem_q.ret;

    Mig3LoadData u_mig3_load_data(
        .funct3(ex_mem_q.funct3), .offset(ex_mem_q.offset), .word(dcache_rsp.data),
        .load_data(mem_load_data));

    // A load waits in MEM/WB until its word comes; it writes rd and retires then.
    assign mem_wait = ex_mem_q.valid && ex_mem_q.load && !dcache_rsp.valid;

    // Write back: rd_addr of the entry is 0 when nothing is written (RVFI: traps, x0;
    // EX builds it from ex_done). A bubble keeps old fields (Mig3PipeReg clears only
    // valid, also at reset), so valid gates the write.
    assign mem_rd       = (ex_mem_q.valid && !mem_wait) ? mem_ret.rd_addr : '0;
    assign mem_rd_write = mem_rd != '0;
    assign mem_rd_data  = ex_mem_q.load ? mem_load_data : mem_ret.rd_wdata;

    // Retire, RVFI: the entry from EX, with what MEM/WB adds.
    always_ff @(posedge clk)
        if (!rst_n)            retire_order <= '0;
        else if (retire.valid) retire_order <= retire_order + 1'b1;

    always_comb begin
        retire           = mem_ret;
        retire.valid     = ex_mem_q.valid && !mem_wait;
        retire.bubble    = mem_wait ? BUBBLE_DMEM : ex_mem_q.bubble;
        retire.order     = retire_order;
        retire.rd_wdata  = mem_rd_write ? mem_rd_data : '0;
        retire.mem_rdata = mem_ret.mem_rmask != '0 ? dcache_rsp.data : '0;
    end

    // Pipeline view: the slots of the stages and their moves (pipe_trace_t, Mig3Pkg).
    assign pipe_trace = '{if_req:   if_taken,
                          if_pc:    icache_req.addr,
                          if2:      if2_slot,
                          id:       id_fetch,
                          ex:       ex_fetch,
                          mem:      '{valid:  ex_mem_q.valid,
                                      bubble: mem_wait ? BUBBLE_DMEM : ex_mem_q.bubble,
                                      pc:     mem_ret.pc_rdata[WIDTH-1:IADDR_START]},
                          redirect: if_ctrl.redirect || !if_ctrl.run,
                          if2_wait:  if2_wait,
                          if2_stall: if2_keep,
                          id_stall:  if_ctrl.stall,
                          ex_stall: pipe_ctrl.ex_stall,
                          ex_flush: pipe_ctrl.ex_flush,
                          mem_wait: mem_wait};

    assign dbg_rsp.halt_pc   = halt_pc;
    assign dbg_rsp.reg_rdata = dbg_reg_rdata;

    // The data channel keeps the valid/ready rules: a request the D-cache does not take
    // stays as it is.
    `DC_ASSERT_NEXT(a_dmem_req_held, dcache_req.valid && !dcache_rsp.ready,
                    dcache_req.valid && $stable(dcache_req))
    // The D-cache answers only the load in MEM/WB (one request in flight).
    `DC_ASSERT(a_dmem_answer_expected, !dcache_rsp.valid || (ex_mem_q.valid && ex_mem_q.load))
    // A load that waits in MEM/WB for its word stays there, unchanged, until the word comes.
    `DC_ASSERT_NEXT(a_load_wait_held, mem_wait,
                    ex_mem_q.valid && ex_mem_q.load && $stable(ex_mem_q))

endmodule

/* Mig2 control: when the core runs, where it fetches, when it traps and when it stops,
 * and the stalls and flushes of the pipeline (IF | ID | EX | MEM/WB).
 *
 * Traps (machine mode): when the instruction in EX faults, it does not complete (no
 * register or memory write, minstret does not count it), it retires as a trap with
 * ex_trap (cause and tval for mcause and mtval, see Mig2Csr) and fetch goes to mtvec.
 * Faults: cause, tval:
 * - taken jump or branch to an address not divisible by 4: misaligned fetch, the target;
 * - illegal instruction, CSR instruction on a CSR that does not exist or writing a
 *   read-only CSR: illegal instruction, the instruction;
 * - EBREAK while ebreak_halt=0: breakpoint, its address;
 * - load or store with a misaligned address: misaligned load or store, the address;
 * - ECALL: machine ECALL, 0.
 * MRET goes to mepc. EBREAK while ebreak_halt=1 (a debugger is attached; dcsr.ebreakm of
 * the debug spec) completes and halts the core: fetch stops and ID is flushed at once,
 * halt=1 comes the cycle after EBREAK retired in MEM/WB; halt_pc is its address, nothing
 * is in flight; resume=1 runs again from halt_pc + 4 (a redirect: IF has fetched beyond
 * EBREAK).
 * A redirect from EX (branch guessed wrong, JALR, trap, MRET; resume) drops the
 * instructions in ID and IF (two bubbles). The BTB of Mig2Fetch sends fetch to the target
 * of a branch or JAL it knows in IF already (no bubble). ID checks what the BTB said: it
 * trusts a hit that fits the instruction, corrects one that does not (one bubble,
 * BUBBLE_BTB_FIX; two pcs share an entry) and clears its entry. Without a hit, ID
 * redirects fetch to pc + imm for a JAL (always taken) and for a conditional branch
 * guessed taken (Mig2BranchPredict) when the instruction leaves ID: only the instruction
 * in IF is dropped (one bubble). EX redirects when the outcome differs from where fetch
 * went: a taken branch that fetch did not follow goes to its target, one that fetch
 * followed but is not taken to the next instruction; EX updates the BTB with every branch
 * and JAL that completes. An
 * instruction behind a redirect or halt in EX is dropped with ID; a jump or branch to a
 * misaligned target traps in EX. ex_muldiv_stall (division not done) keeps the
 * instruction in EX: ID and IF hold.
 * Interlock: results are forwarded to ID (Mig2Forward), except load data, which comes
 * in MEM/WB: the instruction in ID waits one cycle while it reads the rd of a load in
 * EX (load-use); EX gets a bubble meanwhile.
 * Every bubble carries its reason (bubble_e, Mig2Pkg): the redirect class (JAL, branch
 * guessed taken, BTB corrected from ID; branch guessed wrong, JALR or return, trap, MRET
 * from EX), fill
 * for resume and for the slot the halting EBREAK flushes, load-use for the interlock.
 * ex_done=1: the instruction in EX completes: CSR write and minstret now; it writes rd
 * and retires in MEM/WB, which it always reaches.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "dark_circuit_assert.svh"

module Mig2Control import Mig2Pkg::*, RiscvPkg::*; (
    input  wire                        clk,
    input  wire                        rst_n,       // synchronous reset, active low
    input  iaddr_t                     if_pc,       // address IF requests from imem
    // Only valid and pc are used.
    /* verilator lint_off UNUSEDSIGNAL */
    input  fetch_t                     id_fetch,    // instruction in ID: valid and pc
    /* verilator lint_on UNUSEDSIGNAL */
    // Only uses_rs1, uses_rs2, rs1, rs2, br and imm are used.
    /* verilator lint_off UNUSEDSIGNAL */
    input  decoded_t                   id_dec,      // instruction in ID taken apart
    /* verilator lint_on UNUSEDSIGNAL */
    input  wire                        id_pred_taken, // branch in ID guessed taken
    // Only hit and taken are used: ID checks where fetch went.
    /* verilator lint_off UNUSEDSIGNAL */
    input  btb_pred_t                  id_btb,      // what the BTB said in IF for it
    /* verilator lint_on UNUSEDSIGNAL */
    // Only valid and pc are used.
    /* verilator lint_off UNUSEDSIGNAL */
    input  fetch_t                     ex_fetch,    // instruction in EX: valid and pc
    /* verilator lint_on UNUSEDSIGNAL */
    input  insn_t                      ex_insn,     // for mtval of illegal instructions
    // Only sys, mem, br, rd_we and rd are used.
    /* verilator lint_off UNUSEDSIGNAL */
    input  decoded_t                   ex_dec,      // instruction in EX taken apart
    /* verilator lint_on UNUSEDSIGNAL */
    input  wire                        ex_redirected, // fetch went to its target
    // Only hit and counter are used: they go into the update of the BTB.
    /* verilator lint_off UNUSEDSIGNAL */
    input  btb_pred_t                  ex_btb,      // what the BTB said in IF for it
    /* verilator lint_on UNUSEDSIGNAL */
    input  word_t                      ex_addr,     // load/store address, for mtval
    input  branch_t                    ex_branch,   // next pc of the instruction in EX
    input  wire                        ex_lsu_misaligned, // load/store address not aligned: a fault
    input  wire                        ex_csr_illegal,    // CSR instruction can not be done
    input  wire                        ex_muldiv_stall,   // division of the instruction in EX not done
    input  csr_t                       csr,         // mtvec, mepc
    input  wire                        ebreak_halt, // debug: EBREAK halts instead of trapping
    input  wire                        resume,      // debug: continue after EBREAK
    output fetch_ctrl_t                fetch_ctrl,
    output pipe_ctrl_t                 pipe_ctrl,
    output btb_update_t                btb_update,  // a branch or JAL completes in EX
    output btb_inval_t                 btb_inval,   // the BTB was wrong for the insn in ID
    output wire                        id_redirected, // fetch went to the target of the
                                                    // insn in ID; carried to EX
    output wire                        ex_done,
    output trap_t                      ex_trap,
    output iaddr_t                     ex_next_pc,  // next pc of the instruction in EX (retire)
    output wire                        halt,
    output iaddr_t                     halt_pc
);
    logic       ex_stall;    // the instruction in EX stays for another cycle
    assign ex_stall = ex_muldiv_stall;

    logic       running;     // 1 from reset until EBREAK halts the core, again after resume
    logic       ex_stop;     // EBREAK in EX halts the core
    logic       ex_mret;     // MRET in EX
    logic       ex_fault;    // instruction in EX traps
    excp_code_t ex_cause;
    word_t      ex_tval;
    logic       resuming;    // resume while halted
    logic       ex_redirect; // EX (or resume) redirects fetch: ID and IF are dropped
    logic       ex_wrong;    // the jump or branch in EX does not go where ID sent fetch
    iaddr_t     ex_branch_pc; // where the jump or branch in EX goes: target or next insn
    logic       ex_jal;      // JAL in EX
    logic       id_jal;      // JAL in ID
    logic       id_taken;    // ID sends fetch to the target: JAL, branch guessed taken
    logic       id_btb_ok;   // the BTB hit fits the instruction in ID: ID trusts it
    logic       id_btb_fix;  // the BTB hit does not fit: ID corrects fetch, clears the entry
    logic       id_redirect; // ID redirects fetch when the instruction moves
    iaddr_t     id_redirect_pc; // where ID sends fetch: the target or the next instruction
    word_t      id_target;   // target of the instruction in ID: pc + imm, byte address
    logic       id_moves;    // the instruction in ID goes to EX at the rising edge
    logic       ex_writes;   // the instruction in EX writes a register at the end of its cycle
    logic       mem_halting; // the EBREAK that halts the core is in MEM/WB, it retires now
    logic       id_load_use; // ID reads the rd of a load in EX: its data comes in MEM/WB
    logic       id_hazard;   // the instruction in ID must wait
    logic       flush_id;    // the instruction in ID must not go on
    bubble_e    redirect_why; // reason of the bubbles of a redirect

    assign ex_stop = ex_fetch.valid && ex_dec.sys.ebreak && ebreak_halt;
    assign ex_mret = ex_fetch.valid && ex_dec.sys.mret;

    // Fault of the instruction in EX; at most one source applies to an instruction.
    always_comb begin
        ex_fault = ex_fetch.valid;
        ex_cause = '0;
        ex_tval  = '0;
        if (ex_dec.sys.illegal || ex_csr_illegal) begin
            ex_cause = CAUSE_ILLEGAL_INSTRUCTION;
            ex_tval  = ex_insn;
        end else if (ex_dec.sys.ecall)
            ex_cause = CAUSE_MACHINE_ECALL;
        else if (ex_dec.sys.ebreak && !ebreak_halt) begin
            ex_cause = CAUSE_BREAKPOINT;
            ex_tval  = {ex_fetch.pc, {IADDR_START{1'b0}}};
        end else if (ex_branch.taken && ex_branch.misaligned) begin
            // The target byte address: misaligned means bit 1 is set, bit 0 is always 0
            // (JALR clears it, other offsets are even).
            ex_cause = CAUSE_MISALIGNED_FETCH;
            ex_tval  = {ex_branch.target, 2'b10};
        end else if (ex_lsu_misaligned) begin
            ex_cause = ex_dec.mem.write ? CAUSE_MISALIGNED_STORE : CAUSE_MISALIGNED_LOAD;
            ex_tval  = ex_addr;
        end else
            ex_fault = 1'b0;
    end

    assign ex_trap.valid = ex_fault;
    assign ex_trap.cause = ex_cause;
    assign ex_trap.tval  = ex_tval;

    // EBREAK decides in EX (ex_stop: fetch stops, ID is flushed); the core halts after
    // it retired in MEM/WB, so halt=1 comes the cycle after its retire.
    always_ff @(posedge clk)
        if (!rst_n) mem_halting <= 1'b0;
        else        mem_halting <= ex_stop;

    always_ff @(posedge clk)
        if (!rst_n)              running <= 1'b1;
        else if (mem_halting)    running <= 1'b0;
        else if (halt && resume) running <= 1'b1;

    always_ff @(posedge clk)
        if (ex_stop) halt_pc <= ex_fetch.pc;

    assign resuming = halt && resume;
    // EX redirects when a jump or branch does not go where ID sent fetch: taken, but ID did
    // not redirect (guessed not taken, JALR), or ID redirected (guessed taken) but not taken.
    assign ex_jal       = ex_dec.br.jump && !ex_dec.br.target_rs1;
    assign ex_wrong     = ex_fetch.valid && ex_branch.taken != ex_redirected;
    assign ex_branch_pc = ex_branch.taken ? ex_branch.target : ex_fetch.pc + 1'b1;
    assign ex_redirect  = ex_fault || ex_mret || ex_wrong || resuming;
    assign flush_id     = ex_redirect || ex_stop;

    // Class of a redirect from EX: a branch guessed wrong (either way) or JALR by its kind,
    // a trap, MRET; a resume refills the pipeline.
    always_comb
        if (ex_fault)              redirect_why = BUBBLE_TRAP;
        else if (ex_mret)          redirect_why = BUBBLE_XRET;
        else if (resuming)         redirect_why = BUBBLE_FILL;
        else if (ex_dec.br.branch) redirect_why = BUBBLE_COND_BRANCH;
        else if (ex_dec.br.ret)    redirect_why = BUBBLE_RET;
        else                       redirect_why = BUBBLE_INDIR_JUMP;

    // ID acts (redirects now; pushes to a return stack, shifts a history later) only for an
    // instruction that goes on to EX: once per instruction, never on the wrong path. It
    // stays while EX holds a division or it waits for load data; it is dropped when an
    // older instruction in EX redirects or halts.
    assign id_moves = id_fetch.valid && !ex_stall && !id_hazard && !flush_id;

    // ID sends fetch to pc + imm for a JAL (always taken) and for a conditional branch
    // guessed taken. A target not divisible by 4 is a fault: EX traps, ID does not redirect.
    assign id_jal      = id_fetch.valid && id_dec.br.jump && !id_dec.br.target_rs1;
    assign id_target   = {id_fetch.pc, {IADDR_START{1'b0}}} + id_dec.imm;
    assign id_taken    = (id_jal || (id_fetch.valid && id_pred_taken)) &&
                         !target_misaligned(id_target);

    // What the BTB said in IF: a hit fits when the instruction is a branch or a JAL and
    // fetch went where it says: to pc + imm (the address IF requests now; it holds while ID
    // waits) when taken; a JAL must be taken. ID trusts a hit that fits, also its direction
    // (no static guess on top: the counter knows the branch). A hit that does not fit (two
    // pcs share an entry; never when the tag covers imem) is corrected as if the BTB had
    // missed, and its entry is cleared. Without a hit, ID decides as before.
    assign id_btb_ok  = id_btb.hit &&
                        ((id_dec.br.branch &&
                          (!id_btb.taken || if_pc == id_target[WIDTH-1:IADDR_START])) ||
                         (id_jal && id_btb.taken && if_pc == id_target[WIDTH-1:IADDR_START]));
    assign id_btb_fix = id_fetch.valid && id_btb.hit && !id_btb_ok;

    // ID redirects when it moves: without a hit for its target; for a hit that does not fit,
    // when fetch must go to the target or went to a wrong one (else fetch went on to the
    // next instruction, which is right).
    assign id_redirect    = id_moves && (id_btb.hit ? id_btb_fix && (id_taken || id_btb.taken)
                                                    : id_taken);
    assign id_redirect_pc = id_taken ? id_target[WIDTH-1:IADDR_START] : id_fetch.pc + 1'b1;
    // Fetch went to the target: by the BTB in IF (a hit that fits), else by ID.
    assign id_redirected  = id_btb_ok ? id_btb.taken : id_taken;

    // The BTB learns every branch and JAL that completes in EX (not one that traps), with
    // what it said in IF; ID clears an entry that did not fit, once (when it moves).
    assign btb_update = '{en:      ex_done && (ex_dec.br.branch || ex_jal),
                          pc:      ex_fetch.pc,
                          hit:     ex_btb.hit,
                          counter: ex_btb.counter,
                          taken:   ex_branch.taken,
                          target:  ex_branch.target};
    assign btb_inval  = '{en: id_btb_fix && id_moves, pc: id_fetch.pc};

    // Interlock: other results are forwarded to ID (Mig2Forward), but a load's data comes
    // from dmem in MEM/WB, one cycle after EX, so it can not be forwarded to ID while the
    // load is in EX. The instruction in ID that reads the load's rd waits one cycle, EX gets
    // a bubble. uses_rs1/uses_rs2: only real register reads count, not immediate bits in
    // the rs fields.
    logic ex_load;          // the instruction in EX is a load that writes a register
    logic id_reads_ex_rd;   // the instruction in ID reads the register EX writes

    assign ex_writes      = ex_fetch.valid && ex_dec.rd_we && ex_dec.rd != '0;
    assign ex_load        = ex_writes && ex_dec.mem.read;
    assign id_reads_ex_rd = (id_dec.uses_rs1 && id_dec.rs1 == ex_dec.rd) ||
                            (id_dec.uses_rs2 && id_dec.rs2 == ex_dec.rd);
    assign id_load_use    = ex_load && id_reads_ex_rd;
    assign id_hazard   = id_fetch.valid && id_load_use;

    assign ex_done             = ex_fetch.valid && !ex_fault && !ex_stall;
    assign fetch_ctrl.run      = rst_n && running && !ex_stop && !mem_halting;
    assign fetch_ctrl.stall    = (ex_stall || id_hazard) && !flush_id;
    assign fetch_ctrl.redirect = ex_redirect || id_redirect;
    assign fetch_ctrl.why      = ex_redirect ? redirect_why : id_btb_fix ? BUBBLE_BTB_FIX :
                                 id_jal ? BUBBLE_DIR_JUMP : BUBBLE_PRED_TAKEN;
    assign fetch_ctrl.target   = ex_fault ? csr.mtvec : ex_mret ? csr.mepc :
                                 resuming ? halt_pc + 1'b1 :
                                 ex_redirect ? ex_branch_pc : id_redirect_pc;
    assign pipe_ctrl.ex_stall  = ex_stall;
    assign pipe_ctrl.ex_flush  = !ex_stall && (id_hazard || flush_id);
    assign pipe_ctrl.ex_why    = ex_redirect ? redirect_why :
                                 ex_stop ? BUBBLE_FILL : BUBBLE_LOAD_USE;

    // Next pc of the instruction in EX, for retire: where EX redirects, else where the jump
    // or branch goes (redirected from ID or not taken), else the next instruction.
    assign ex_next_pc = ex_redirect ? fetch_ctrl.target : ex_branch_pc;
    assign halt                = !running;

    // Halted: nothing is in EX, so no redirect comes from EX (only resume redirects).
    `DC_ASSERT(a_halted_ex_empty, !(halt && ex_fetch.valid))
    // At most one fault source applies to an instruction (the fault block relies on it).
    `DC_ASSERT(a_one_fault, !ex_fetch.valid ||
               $onehot0({ex_dec.sys.illegal || ex_csr_illegal, ex_dec.sys.ecall,
                         ex_dec.sys.ebreak && !ebreak_halt,
                         ex_branch.taken && ex_branch.misaligned, ex_lsu_misaligned}))
    // A stalled instruction stays in EX for the next cycle.
    `DC_ASSERT_NEXT(a_ex_held, ex_stall, ex_fetch.valid && $stable(ex_fetch.pc))
    // ID redirects only for an instruction that moves to EX in this cycle.
    `DC_ASSERT(a_id_redirect_moves, !id_redirect || (!pipe_ctrl.ex_stall && !pipe_ctrl.ex_flush))
    // Fetch is never told to redirect and to stall in the same cycle.
    `DC_ASSERT(a_redirect_no_stall, !(fetch_ctrl.redirect && fetch_ctrl.stall))
    // Fetch went to the target of a JAL in EX (IF or ID), unless it traps (misaligned).
    `DC_ASSERT(a_ex_jal_redirected,
               !(ex_fetch.valid && ex_jal) || ex_redirected || ex_branch.misaligned)
    // ID redirects only for a JAL or a conditional branch, or to correct the BTB; it
    // guesses only branches.
    `DC_ASSERT(a_id_redirect_jump,
               !id_redirect || id_dec.br.jump || id_dec.br.branch || id_btb_fix)
    `DC_ASSERT(a_pred_branch, !id_pred_taken || id_dec.br.branch)
    // The BTB predicts taken only on a hit; ID does not redirect again after a hit that fits.
    `DC_ASSERT(a_btb_taken_hit, !id_fetch.valid || !id_btb.taken || id_btb.hit)
    `DC_ASSERT(a_btb_trusted, !(id_btb_ok && id_redirect))

endmodule

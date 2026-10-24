/* Mig1 control: when the core runs, where it fetches, when it traps and when it stops,
 * and the stalls and flushes of the pipeline (IF | ID | EX | MEM/WB).
 *
 * Traps (machine mode): when the instruction in EX faults, it does not complete (no
 * register or memory write, minstret does not count it), it retires as a trap with
 * ex_trap (cause and tval for mcause and mtval, see Mig1Csr) and fetch goes to mtvec.
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
 * A redirect (taken jump or branch, trap, MRET in EX; resume) drops the instructions in
 * ID and IF (two bubbles). ex_muldiv_stall (division not done) keeps the instruction in
 * EX: ID and IF hold.
 * Interlock: results are forwarded to ID (Mig1Forward), except load data, which comes
 * in MEM/WB: the instruction in ID waits one cycle while it reads the rd of a load in
 * EX (load-use); EX gets a bubble meanwhile.
 * ex_done=1: the instruction in EX completes: CSR write and minstret now; it writes rd
 * and retires in MEM/WB, which it always reaches.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "dark_circuit_assert.svh"

module Mig1Control import Mig1Pkg::*, RiscvPkg::*; (
    input  wire                        clk,
    input  wire                        rst_n,       // synchronous reset, active low
    input  wire                        id_valid,    // an instruction is in ID
    // Only uses_rs1, uses_rs2, rs1 and rs2 are used.
    /* verilator lint_off UNUSEDSIGNAL */
    input  decoded_t                   id_dec,      // instruction in ID taken apart
    /* verilator lint_on UNUSEDSIGNAL */
    input  fetch_t                     ex_fetch,    // instruction in EX: valid and pc
    input  insn_t                      ex_insn,     // for mtval of illegal instructions
    // Only sys, mem, rd_we and rd are used.
    /* verilator lint_off UNUSEDSIGNAL */
    input  decoded_t                   ex_dec,      // instruction in EX taken apart
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
    output wire                        ex_done,
    output trap_t                      ex_trap,
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
    logic       redirect;
    logic       ex_writes;   // the instruction in EX writes a register at the end of its cycle
    logic       mem_halting; // the EBREAK that halts the core is in MEM/WB, it retires now
    logic       id_load_use; // ID reads the rd of a load in EX: its data comes in MEM/WB
    logic       id_hazard;   // the instruction in ID must wait
    logic       flush_id;    // the instruction in ID must not go on

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
    assign redirect = ex_fault || ex_mret || (ex_fetch.valid && ex_branch.taken) || resuming;
    assign flush_id = redirect || ex_stop;

    // Interlock: other results are forwarded to ID (Mig1Forward), but a load's data comes
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
    assign id_hazard   = id_valid && id_load_use;

    assign ex_done             = ex_fetch.valid && !ex_fault && !ex_stall;
    assign fetch_ctrl.run      = rst_n && running && !ex_stop && !mem_halting;
    assign fetch_ctrl.stall    = (ex_stall || id_hazard) && !flush_id;
    assign fetch_ctrl.redirect = redirect;
    assign fetch_ctrl.target   = ex_fault ? csr.mtvec : ex_mret ? csr.mepc :
                                 resuming ? halt_pc + 1'b1 : ex_branch.target;
    assign pipe_ctrl.ex_stall  = ex_stall;
    assign pipe_ctrl.ex_flush  = !ex_stall && (id_hazard || flush_id);
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

endmodule

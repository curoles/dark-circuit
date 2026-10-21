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
 * A redirect (taken jump or branch, trap, MRET in EX; resume) drops the instructions in
 * ID and IF (two bubbles). muldiv_stall (division not done) keeps the instruction in EX:
 * ID and IF hold.
 * Interlock: results are forwarded to ID (Mig2Forward), except load data, which comes
 * in MEM/WB: the instruction in ID waits one cycle while it reads the rd of a load in
 * EX (load-use); EX gets a bubble meanwhile.
 * ex_done=1: the instruction in EX completes: CSR write and minstret now; it writes rd
 * and retires in MEM/WB, which it always reaches.
 */
module Mig2Control import Mig2Pkg::*, RiscvPkg::*; (
    input  wire                        clk,
    input  wire                        rst_n,       // synchronous reset, active low
    input  wire                        id_valid,    // an instruction is in ID
    // Only uses_rs1, uses_rs2, rs1 and rs2 are used.
    /* verilator lint_off UNUSEDSIGNAL */
    input  decoded_t                   id_dec,      // instruction in ID taken apart
    /* verilator lint_on UNUSEDSIGNAL */
    input  fetch_t                     ex,          // instruction in EX: valid and pc
    input  insn_t                      ex_insn,     // for mtval of illegal instructions
    // Only kind, rd_we and rd are used.
    /* verilator lint_off UNUSEDSIGNAL */
    input  decoded_t                   ex_dec,      // instruction in EX taken apart
    /* verilator lint_on UNUSEDSIGNAL */
    input  word_t                      ex_addr,     // load/store address, for mtval
    input  branch_t                    branch,      // next pc of the instruction in EX
    input  wire                        lsu_misaligned, // load/store address not aligned: a fault
    input  wire                        csr_illegal, // CSR instruction can not be done
    input  wire                        muldiv_stall, // division of the instruction in EX not done
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
    // Fields of the inputs, selected with assign: Icarus warns about selects in always_comb.
    logic   valid;
    iaddr_t pc;
    kind_t  kind;
    logic   taken;
    logic   misaligned_target;
    iaddr_t target;
    logic   ex_stall;       // the instruction in EX stays for another cycle
    iaddr_t mtvec;
    iaddr_t mepc;
    logic   id_uses_rs1;
    logic   id_uses_rs2;
    reg_id_t   id_rs1;
    reg_id_t   id_rs2;
    logic   ex_rd_we;
    reg_id_t   ex_rd;
    assign valid             = ex.valid;
    assign pc                = ex.pc;
    assign kind              = ex_dec.kind;
    assign taken             = branch.taken;
    assign misaligned_target = branch.misaligned;
    assign target            = branch.target;
    assign ex_stall          = muldiv_stall;
    assign mtvec             = csr.mtvec;
    assign mepc              = csr.mepc;
    assign id_uses_rs1       = id_dec.uses_rs1;
    assign id_uses_rs2       = id_dec.uses_rs2;
    assign id_rs1            = id_dec.rs1;
    assign id_rs2            = id_dec.rs2;
    assign ex_rd_we          = ex_dec.rd_we;
    assign ex_rd             = ex_dec.rd;

    logic       running;    // 1 from reset until EBREAK halts the core, again after resume
    logic       stop;       // EBREAK in EX halts the core
    logic       mret;       // MRET in EX
    logic       trap;       // instruction in EX traps
    logic [4:0] cause;
    word_t      tval;
    logic       resuming;   // resume while halted
    logic       redirect;
    logic       ex_writes;  // the instruction in EX writes a register at the end of its cycle
    logic       halting;    // the EBREAK that halts the core is in MEM/WB, it retires now
    logic       load_use;   // ID reads the rd of a load in EX: its data comes in MEM/WB
    logic       hazard;
    logic       flush_id;   // the instruction in ID must not go on

    assign stop = ex.valid && kind == KIND_EBREAK && ebreak_halt;
    assign mret = ex.valid && kind == KIND_MRET;

    // Fault of the instruction in EX; at most one source applies to an instruction.
    always_comb begin
        trap  = valid;
        cause = '0;
        tval  = '0;
        if (kind == KIND_ILLEGAL || csr_illegal) begin
            cause = CAUSE_ILLEGAL_INSTRUCTION;
            tval  = ex_insn;
        end else if (kind == KIND_ECALL)
            cause = CAUSE_MACHINE_ECALL;
        else if (kind == KIND_EBREAK && !ebreak_halt) begin
            cause = CAUSE_BREAKPOINT;
            tval  = {pc, {IADDR_START{1'b0}}};
        end else if (taken && misaligned_target) begin
            // The target byte address: misaligned means bit 1 is set, bit 0 is always 0
            // (JALR clears it, other offsets are even).
            cause = CAUSE_MISALIGNED_FETCH;
            tval  = {target, 2'b10};
        end else if (lsu_misaligned) begin
            cause = (kind == KIND_STORE) ? CAUSE_MISALIGNED_STORE : CAUSE_MISALIGNED_LOAD;
            tval  = ex_addr;
        end else
            trap  = 1'b0;
    end

    assign ex_trap.valid = trap;
    assign ex_trap.cause = cause;
    assign ex_trap.tval  = tval;

    // EBREAK decides in EX (stop: fetch stops, ID is flushed); the core halts after
    // it retired in MEM/WB, so halt=1 comes the cycle after its retire.
    always_ff @(posedge clk)
        if (!rst_n) halting <= 1'b0;
        else        halting <= stop;

    always_ff @(posedge clk)
        if (!rst_n)              running <= 1'b1;
        else if (halting)        running <= 1'b0;
        else if (halt && resume) running <= 1'b1;

    always_ff @(posedge clk)
        if (stop) halt_pc <= ex.pc;

    assign resuming  = halt && resume;
    assign redirect  = trap || mret || (valid && taken) || resuming;
    assign flush_id  = redirect || stop;

    // Interlock: other results are forwarded to ID (Mig2Forward); a load in EX has no data.
    assign ex_writes = valid && ex_rd_we && ex_rd != '0;
    assign load_use  = ex_writes && kind == KIND_LOAD &&
                       ((id_uses_rs1 && id_rs1 == ex_rd) || (id_uses_rs2 && id_rs2 == ex_rd));
    assign hazard    = id_valid && load_use;

    assign ex_done             = valid && !trap && !ex_stall;
    assign fetch_ctrl.run      = rst_n && running && !stop && !halting;
    assign fetch_ctrl.stall    = (ex_stall || hazard) && !flush_id;
    assign fetch_ctrl.redirect = redirect;
    assign fetch_ctrl.target   = trap ? mtvec : mret ? mepc : resuming ? halt_pc + 1'b1 : target;
    assign pipe_ctrl.ex_stall  = ex_stall;
    assign pipe_ctrl.ex_flush  = !ex_stall && (hazard || flush_id);
    assign halt                = !running;

endmodule

/* Mig1 control: when the core runs, where it fetches, when it traps and when it stops.
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
 * the debug spec) completes and halts the core: halt=1, halt_pc is its address, nothing
 * more is fetched, nothing is in flight; resume=1 runs again from halt_pc + 4, where
 * the PC already is (it did not advance in the cycle of EBREAK).
 * A redirect (taken jump or branch, trap, MRET) drops the instruction fetched in the
 * same cycle (one bubble). lsu.stall (load waiting for data) and muldiv_stall (division
 * not done) keep the instruction in EX: fetch holds, the instruction completes later.
 * ex_done=1: the instruction in EX completes, it writes rd and retires.
 */
module Mig1Control import Mig1Pkg::*, RiscvPkg::*; (
    input  wire                        clk,
    input  wire                        rst_n,       // synchronous reset, active low
    input  fetch_t                     ex,          // instruction in EX: valid and pc
    input  logic [INSN_WIDTH-1:0]      ex_insn,     // insn_t, for mtval of illegal instructions
    // Only kind is used.
    /* verilator lint_off UNUSEDSIGNAL */
    input  decoded_t                   ex_dec,      // instruction in EX taken apart
    /* verilator lint_on UNUSEDSIGNAL */
    input  logic [WIDTH-1:0]           ex_addr,     // word_t: load/store address, for mtval
    input  branch_t                    branch,      // next pc of the instruction in EX
    input  lsu_t                       lsu,         // stall and fault of loads and stores
    input  wire                        csr_illegal, // CSR instruction can not be done
    input  wire                        muldiv_stall, // division of the instruction in EX not done
    input  csr_t                       csr,         // mtvec, mepc
    input  wire                        ebreak_halt, // debug: EBREAK halts instead of trapping
    input  wire                        resume,      // debug: continue after EBREAK
    output fetch_ctrl_t                fetch_ctrl,
    output wire                        ex_done,
    output trap_t                      ex_trap,
    output wire                        halt,
    output logic [WIDTH-1:IADDR_START] halt_pc      // iaddr_t
);
    // Fields of the inputs, selected with assign: Icarus warns about selects in always_comb.
    logic   valid;
    iaddr_t pc;
    kind_t  kind;
    logic   taken;
    logic   misaligned_target;
    iaddr_t target;
    logic   lsu_misaligned;
    logic   lsu_stall;
    logic   ex_stall;       // the instruction in EX stays for another cycle
    iaddr_t mtvec;
    iaddr_t mepc;
    assign valid             = ex.valid;
    assign pc                = ex.pc;
    assign kind              = ex_dec.kind;
    assign taken             = branch.taken;
    assign misaligned_target = branch.misaligned;
    assign target            = branch.target;
    assign lsu_misaligned    = lsu.misaligned;
    assign lsu_stall         = lsu.stall;
    assign ex_stall          = lsu_stall || muldiv_stall;
    assign mtvec             = csr.mtvec;
    assign mepc              = csr.mepc;

    logic       running;    // 1 from reset until EBREAK halts the core, again after resume
    logic       stop;       // EBREAK in EX halts the core
    logic       mret;       // MRET in EX
    logic       trap;       // instruction in EX traps
    logic [4:0] cause;
    word_t      tval;

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

    always_ff @(posedge clk)
        if (!rst_n)              running <= 1'b1;
        else if (stop)           running <= 1'b0;
        else if (halt && resume) running <= 1'b1;

    always_ff @(posedge clk)
        if (stop) halt_pc <= ex.pc;

    assign ex_done             = ex.valid && !trap && !ex_stall;
    assign fetch_ctrl.run      = rst_n && running && !stop;
    assign fetch_ctrl.stall    = ex_stall;
    assign fetch_ctrl.redirect = trap || mret || (ex.valid && taken);
    assign fetch_ctrl.target   = trap ? mtvec : mret ? mepc : target;
    assign halt                = !running;

endmodule

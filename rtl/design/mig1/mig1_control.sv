/* Mig1 control: when the core runs, where it fetches, and when it stops.
 *
 * The core runs from reset until the instruction in EX stops it:
 * - EBREAK: it completes and the core halts (halt=1);
 * - a fault: ECALL, an illegal instruction, a taken jump or branch to a misaligned
 *   target, or a load or store with a misaligned address: halt=1 and illegal=1,
 *   the instruction does not complete (no register write, no memory write, no retire).
 * halt_pc is the address of the instruction that stopped the core; nothing more is
 * fetched, nothing is in flight. resume=1 while halted after EBREAK runs again from
 * halt_pc + 4: the PC already holds it, it did not advance in the cycle of EBREAK.
 * illegal=1 is final, resume does nothing then.
 * A taken jump or branch redirects fetch to its target; the instruction fetched
 * in the same cycle is dropped (one bubble). lsu.stall keeps the instruction in EX
 * for another cycle (load waiting for data): fetch holds, the instruction completes later.
 * ex_done=1: the instruction in EX completes, it writes rd and retires.
 * ex_trap=1: the instruction in EX faults; it retires as a trap (RVFI), without writes.
 */
module Mig1Control import Mig1Pkg::*; (
    input  wire                        clk,
    input  wire                        rst_n,      // synchronous reset, active low
    input  fetch_t                     ex,         // instruction in EX: valid and pc
    // Only kind is used.
    /* verilator lint_off UNUSEDSIGNAL */
    input  decoded_t                   ex_dec,     // instruction in EX taken apart
    /* verilator lint_on UNUSEDSIGNAL */
    input  branch_t                    branch,     // next pc of the instruction in EX
    input  lsu_t                       lsu,        // stall and fault of loads and stores
    input  wire                        resume,     // debug: continue after EBREAK
    output fetch_ctrl_t                fetch_ctrl,
    output wire                        ex_done,
    output wire                        ex_trap,
    output wire                        halt,
    output logic                       illegal,
    output logic [WIDTH-1:IADDR_START] halt_pc     // iaddr_t
);
    kind_t kind;
    logic  running;  // 1 from reset until the core halts, again after resume
    wire   fault;    // instruction in EX can not complete
    wire   stop;     // instruction in EX is the last one

    assign kind = ex_dec.kind;

    assign fault = ex.valid && ((branch.taken && branch.misaligned) || lsu.misaligned ||
                                kind == KIND_ECALL || kind == KIND_ILLEGAL);
    assign stop  = (ex.valid && kind == KIND_EBREAK) || fault;

    always_ff @(posedge clk)
        if (!rst_n)                          running <= 1'b1;
        else if (stop)                       running <= 1'b0;
        else if (halt && resume && !illegal) running <= 1'b1;

    always_ff @(posedge clk)
        if (!rst_n)     illegal <= 1'b0;
        else if (fault) illegal <= 1'b1;

    always_ff @(posedge clk)
        if (stop) halt_pc <= ex.pc;

    assign ex_done             = ex.valid && !fault && !lsu.stall;
    assign ex_trap             = fault;
    assign fetch_ctrl.run      = rst_n && running && !stop;
    assign fetch_ctrl.stall    = lsu.stall;
    assign fetch_ctrl.redirect = ex.valid && branch.taken && !branch.misaligned;
    assign fetch_ctrl.target   = branch.target;
    assign halt                = !running;

endmodule

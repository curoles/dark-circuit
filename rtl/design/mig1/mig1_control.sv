/* Mig1 control: when the core runs, where it fetches, and when it stops.
 *
 * The core runs from reset until the instruction in EX stops it:
 * - EBREAK: halt=1;
 * - a taken jump or branch to a misaligned target (fault): halt=1 and illegal=1,
 *   the instruction does not complete (no register write, no retire).
 * halt_pc is the address of the instruction that stopped the core; nothing more is fetched.
 * A taken jump or branch redirects fetch to its target; the instruction fetched
 * in the same cycle is dropped (one bubble).
 * ex_done=1: the instruction in EX completes, it writes rd and retires.
 * TODO: ECALL and illegal instructions (decode), resume (debug).
 */
module Mig1Control import Mig1Pkg::*; (
    input  wire                        clk,
    input  wire                        rst_n,      // synchronous reset, active low
    input  fetch_t                     ex,         // instruction in EX: valid and pc
    input  logic [INSN_WIDTH-1:0]      ex_insn,    // insn_t, see Mig1Pkg about ports
    input  branch_t                    branch,     // next pc of the instruction in EX
    output fetch_ctrl_t                fetch_ctrl,
    output wire                        ex_done,
    output wire                        halt,
    output logic                       illegal,
    output logic [WIDTH-1:IADDR_START] halt_pc     // iaddr_t
);
    logic running;  // 1 from reset until the core halts
    wire  fault;    // instruction in EX can not complete
    wire  stop;     // instruction in EX is the last one

    // Until decode is used here, EBREAK is recognized by its encoding.
    assign fault = ex.valid && branch.taken && branch.misaligned;
    assign stop  = (ex.valid && ex_insn == INSN_EBREAK) || fault;

    always_ff @(posedge clk)
        if (!rst_n)    running <= 1'b1;
        else if (stop) running <= 1'b0;

    always_ff @(posedge clk)
        if (!rst_n)     illegal <= 1'b0;
        else if (fault) illegal <= 1'b1;

    always_ff @(posedge clk)
        if (stop) halt_pc <= ex.pc;

    assign ex_done             = ex.valid && !fault;
    assign fetch_ctrl.run      = rst_n && running && !stop;
    assign fetch_ctrl.redirect = ex.valid && branch.taken && !branch.misaligned;
    assign fetch_ctrl.target   = branch.target;
    assign halt                = !running;

endmodule

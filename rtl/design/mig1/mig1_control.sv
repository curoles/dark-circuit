/* Mig1 control: when the core runs and when it stops.
 *
 * The core runs from reset until the instruction in EX is EBREAK; then it halts:
 * halt=1, halt_pc is the address of the EBREAK, nothing more is fetched.
 * TODO: ECALL and illegal instructions (decode), resume (debug), stall and flush.
 */
module Mig1Control import Mig1Pkg::*; (
    input  wire                        clk,
    input  wire                        rst_n,      // synchronous reset, active low
    input  fetch_t                     ex,         // instruction in EX: valid and pc
    input  logic [INSN_WIDTH-1:0]      ex_insn,    // insn_t, see Mig1Pkg about ports
    output fetch_ctrl_t                fetch_ctrl,
    output wire                        halt,
    output logic [WIDTH-1:IADDR_START] halt_pc     // iaddr_t
);
    logic running;  // 1 from reset until the core halts
    wire  stop;     // EBREAK in EX: the last instruction

    // Until decode exists, EBREAK is recognized by its encoding.
    assign stop = ex.valid && ex_insn == INSN_EBREAK;

    always_ff @(posedge clk)
        if (!rst_n)    running <= 1'b1;
        else if (stop) running <= 1'b0;

    always_ff @(posedge clk)
        if (stop) halt_pc <= ex.pc;

    assign fetch_ctrl.run = rst_n && running && !stop;
    assign halt           = !running;

endmodule

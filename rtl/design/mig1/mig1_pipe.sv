/* Mig1 pipeline registers: the instruction of each stage, between the stages.
 *
 * One rule per boundary: reset or flush puts a bubble (valid=0), stall keeps the
 * instruction, else the register takes what the stage before gives. Mig1Control makes
 * the stalls and flushes. The IF/ID boundary is the instruction memory itself (the
 * instruction comes 1 clock after its request, see Mig1Fetch). Now: ID/EX.
 */
module Mig1Pipe import Mig1Pkg::*; (
    input  wire        clk,
    input  wire        rst_n,       // synchronous reset, active low
    input  pipe_ctrl_t ctrl,
    input  id_ex_t     id_ex_d,     // from ID
    output id_ex_t     id_ex_q      // to EX
);
    // Fields of ctrl with assign: Icarus does not support selects in always_ff.
    logic ex_stall;
    logic ex_flush;
    assign ex_stall = ctrl.ex_stall;
    assign ex_flush = ctrl.ex_flush;

    always_ff @(posedge clk)
        if (!rst_n || ex_flush) id_ex_q.valid <= 1'b0;
        else if (!ex_stall)     id_ex_q       <= id_ex_d;

endmodule

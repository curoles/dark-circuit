/* Mig1 pipeline registers: the instruction of each stage, between the stages
 * (Mig1PipeReg: reset or flush puts a bubble, stall keeps the instruction).
 *
 * ID/EX: Mig1Control stalls and flushes it. EX/MEM has no stall or flush: an
 * instruction that leaves EX always completes in MEM/WB. The IF/ID register is in
 * Mig1Fetch (the instruction comes from imem 1 clock after its request).
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module Mig1Pipe import Mig1Pkg::*; (
    input  wire        clk,
    input  wire        rst_n,       // synchronous reset, active low
    input  pipe_ctrl_t ctrl,        // stall, flush and bubble reason of ID/EX, from Mig1Control
    input  id_ex_t     id_ex_d,     // from ID
    output id_ex_t     id_ex_q,     // to EX
    input  ex_mem_t    ex_mem_d,    // from EX
    output ex_mem_t    ex_mem_q     // to MEM/WB
);
    Mig1PipeReg #(.T(id_ex_t)) u_mig1_pipe_reg_id_ex(
        .clk, .rst_n, .stall(ctrl.ex_stall), .flush(ctrl.ex_flush), .why(ctrl.ex_why),
        .d(id_ex_d), .q(id_ex_q));

    Mig1PipeReg #(.T(ex_mem_t)) u_mig1_pipe_reg_ex_mem(
        .clk, .rst_n, .stall(1'b0), .flush(1'b0), .why(BUBBLE_NONE), .d(ex_mem_d), .q(ex_mem_q));

endmodule

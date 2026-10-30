/* Mig2 pipeline registers: the instruction of each stage, between the stages
 * (Mig2PipeReg: reset or flush puts a bubble, stall keeps the instruction).
 *
 * ID/EX: Mig2Control stalls and flushes it. EX/MEM has no flush: an instruction that
 * leaves EX always completes in MEM/WB; it stalls while a load in MEM/WB waits for its word
 * from dmem. The IF/ID register is in Mig2Fetch.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module Mig2Pipe import Mig2Pkg::*; (
    input  wire        clk,
    input  wire        rst_n,       // synchronous reset, active low
    input  pipe_ctrl_t ctrl,        // stalls, flush and bubble reason, from Mig2Control
    input  id_ex_t     id_ex_d,     // from ID
    output id_ex_t     id_ex_q,     // to EX
    input  ex_mem_t    ex_mem_d,    // from EX
    output ex_mem_t    ex_mem_q     // to MEM/WB
);
    Mig2PipeReg #(.T(id_ex_t)) u_mig2_pipe_reg_id_ex(
        .clk, .rst_n, .stall(ctrl.ex_stall), .flush(ctrl.ex_flush), .why(ctrl.ex_why),
        .d(id_ex_d), .q(id_ex_q));

    Mig2PipeReg #(.T(ex_mem_t)) u_mig2_pipe_reg_ex_mem(
        .clk, .rst_n, .stall(ctrl.mem_stall), .flush(1'b0), .why(BUBBLE_NONE), .d(ex_mem_d),
        .q(ex_mem_q));

endmodule

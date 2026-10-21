/* Mig2 pipeline register: the instruction at one stage boundary.
 *
 * T is the struct of the boundary (fetch_t, id_ex_t, ex_mem_t); it must have field valid.
 * Reset or flush puts a bubble: valid=0, the other fields keep their value (they mean
 * nothing while valid=0, so they need no reset). stall keeps the instruction, else the
 * register takes d. Mig2Control makes stall and flush.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module Mig2PipeReg import Mig2Pkg::*; #(
    parameter type T = id_ex_t      // struct of the boundary, with field valid
)(
    input  wire clk,
    input  wire rst_n,              // synchronous reset, active low
    input  wire stall,              // keep the instruction
    input  wire flush,              // bubble
    input  T    d,
    output T    q
);
    always_ff @(posedge clk)
        if (!rst_n || flush) q.valid <= 1'b0;
        else if (!stall)     q       <= d;

endmodule

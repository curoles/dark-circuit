/* Mig2 pipeline register: the instruction at one stage boundary.
 *
 * T is the struct of the boundary (fetch_t, id_ex_t, ex_mem_t); it must have fields valid
 * and bubble (bubble_e: why valid=0). Reset puts a fill bubble, flush a bubble of reason
 * why; a flushed slot that already was a bubble keeps its reason (no new bubble is made).
 * The other fields keep their value (they mean nothing while valid=0, so they need no
 * reset). stall keeps the instruction, else the register takes d. Mig2Control makes
 * stall, flush and why.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
`include "dark_circuit_assert.svh"

module Mig2PipeReg import Mig2Pkg::*; #(
    parameter type T = id_ex_t      // struct of the boundary, with field valid
)(
    input  wire clk,
    input  wire rst_n,              // synchronous reset, active low
    input  wire stall,              // keep the instruction
    input  wire flush,              // bubble
    input  bubble_e why,            // flush: reason of the bubble
    input  T    d,
    output T    q
);
    always_ff @(posedge clk)
        if (!rst_n) begin
            q.valid  <= 1'b0;
            q.bubble <= BUBBLE_FILL;
        end else if (flush) begin
            q.valid  <= 1'b0;
            q.bubble <= d.valid ? why : d.bubble;
        end else if (!stall)
            q <= d;

    // A slot holds an instruction or a bubble with its reason.
    `DC_ASSERT(a_bubble, q.valid == (q.bubble == BUBBLE_NONE))

endmodule

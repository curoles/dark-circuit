/* Latch.
 *
 * See paper:
 * Nonblocking Assignments in Verilog Synthesis, Coding Styles That Kill!
 * Clifford E. Cummings
 * http://www.sunburst-design.com/papers/CummingsSNUG2000SJ_NBA_rev1_2.pdf
 *
 * The SystemVerilog standard (section 9.2.2.3 Latched logic always_latch procedure
 * provides the next example:
 *
 *  always_latch
 *  if(ck) q <= d;
 *
 * @author    Igor Lesik
 * @copyright 2014 Igor Lesik, MIT License
 */
module Latch #(
    parameter WIDTH = 1
)
(
    input  wire [WIDTH-1:0] in,
    input  wire             enable,
    output reg  [WIDTH-1:0] out
);


// Nonblocking assignment as in the standard and Cummings paper above;
// Lint of Verilator asks for blocking assignment in latches.
/* verilator lint_off COMBDLY */
/* verilator lint_off NOLATCH */
always_latch
begin
    if (enable)
        out[WIDTH-1:0] <= in[WIDTH-1:0];
end
/* verilator lint_on NOLATCH */
/* verilator lint_on COMBDLY */

endmodule

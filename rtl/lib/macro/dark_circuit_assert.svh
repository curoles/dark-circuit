/* Assertion macros: invariants written next to the logic they guard.
 *
 * Both macros expect clk and rst_n (synchronous reset, active low) in scope, check at
 * every rising clk edge out of reset and stop the simulation with $fatal: the test fails
 * by its exit code. No semicolon after a macro. sv2v removes assertions, so synthesis
 * never sees them.
 *
 * `DC_ASSERT(name, expr): expr holds. An immediate assertion, Verilator and Icarus; plain
 * always, because Icarus warns about $fatal in always_ff.
 * `DC_ASSERT_NEXT(name, cause, effect): when cause holds at a clock edge, effect holds at
 * the next one. Concurrent SVA, which Icarus does not parse: empty unless
 * DARK_CIRCUIT_USE_SVA is defined (Verilator builds define it).
 */
`ifndef DARK_CIRCUIT_ASSERT_SVH_INCLUDED_
`define DARK_CIRCUIT_ASSERT_SVH_INCLUDED_

`define DC_ASSERT(name, expr) \
    always @(posedge clk) \
        if (rst_n) name: assert (expr) else $fatal(1, `"%m: assertion name failed`");

`ifdef DARK_CIRCUIT_USE_SVA
`define DC_ASSERT_NEXT(name, cause, effect) \
    name: assert property (@(posedge clk) disable iff (!rst_n) (cause) |=> (effect)) \
        else $fatal(1, `"%m: assertion name failed`");
`else
`define DC_ASSERT_NEXT(name, cause, effect)
`endif

`endif

/* Assertion macros: invariants written next to the logic they guard.
 *
 * DC_ASSERT and DC_ASSERT_NEXT expect clk and rst_n (synchronous reset, active low) in
 * scope, check at every rising clk edge out of reset and stop the simulation with $fatal:
 * the test fails by its exit code; sv2v removes them, so synthesis never sees them. No
 * semicolon after a macro.
 *
 * `DC_ASSERT(name, expr): expr holds. An immediate assertion, Verilator and Icarus; plain
 * always, because Icarus warns about $fatal in always_ff.
 * `DC_ASSERT_NEXT(name, cause, effect): when cause holds at a clock edge, effect holds at
 * the next one. Concurrent SVA, which Icarus does not parse: empty unless
 * DARK_CIRCUIT_USE_SVA is defined (Verilator builds define it).
 * `DC_STATIC_ASSERT(name, cond): cond, a constant expression of parameters, holds; checked
 * at elaboration, not in simulation: a generate block with $fatal at module level (no clk),
 * so a false cond stops the build of Verilator and Icarus, and the synthesis (sv2v makes it
 * an initial block with $finish, which Yosys executes). The message is one plain string with
 * the name: Icarus 13 takes no format arguments in an elaboration task.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
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

`define DC_STATIC_ASSERT(name, cond) \
    if (!(cond)) begin: name \
        $fatal(1, `"static assertion name failed`"); \
    end

`endif

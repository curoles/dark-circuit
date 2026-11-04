/* Test macros: named checks, and the hooks of mutant runs (tools/mutate.py, kb records of
 * type mutants, kb/README.md).
 *
 * `DC_TEST_FAIL(name, msg): a check of a test failed: "DC_TEST_FAIL name: msg" and $fatal
 * (the test fails by its exit code). A mutant
 * run may quiet checks by name (the mutant's quiet list, compiled in as DC_TEST_QUIET): they
 * print and go on, so that the check or assertion the mutant expects can fire. msg is a string,
 * $sformatf for values. No semicolon after the macro.
 * `DC_TEST_MUTANT_HOOK(hook): nothing, unless a mutant run defines DC_MUTANT: then the file
 * dc_mutant_<hook>.svh, which the tool writes, with the mutant's verilog_code for that hook
 * (an empty file for every other hook). Put a hook where a mutant may need code, typically
 * after the instance of the block under test in the test's top (hook top) or in a check
 * module (hook check): `initial force u_dut.x = 1'b0;` models a stuck signal without
 * editing the RTL.
 *
 * Both are for tests only. tools/mutate.py adds the defines of a mutant run at the top of
 * this file in its scratch copy.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
`ifndef DARK_CIRCUIT_TEST_SVH_INCLUDED_
`define DARK_CIRCUIT_TEST_SVH_INCLUDED_

`define DC_TEST_FAIL(name, msg) \
    begin \
        if (DcTestPkg::stops(`"name`")) \
            $fatal(1, "DC_TEST_FAIL %s: %s", `"name`", msg); \
        else if (DcTestPkg::quiet_print()) \
            $display("DC_TEST_FAIL %s (quiet): %s", `"name`", msg); \
    end

`ifdef DC_MUTANT
`define DC_TEST_MUTANT_HOOK(hook) `include `"dc_mutant_``hook``.svh`"
`else
`define DC_TEST_MUTANT_HOOK(hook)
`endif

`endif

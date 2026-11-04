/* Helpers of the tests: the named checks of DC_TEST_FAIL (dark_circuit_test.svh).
 *
 * A failed check stops the test with $fatal, unless its name is in the quiet list of a mutant
 * run (DC_TEST_QUIET, comma-separated, defined by tools/mutate.py in its scratch copy): then
 * it prints (the first three times) and the test goes on, so that another check or an
 * assertion can be the one that catches the mutant. Functions, called inside the macro's
 * expressions: Icarus 13 does not take a package task called as a statement.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
`include "dark_circuit_test.svh"

package DcTestPkg;

`ifdef DC_TEST_QUIET
    localparam string QUIET = `DC_TEST_QUIET;
`else
    localparam string QUIET = "";
`endif

    int n_quiet = 0;    // failures of quiet checks so far

    // name is one of the comma-separated names of list.
    function automatic bit listed(input string name, input string list);
        int start;
        start = 0;
        for (int i = 0; i <= list.len(); i++)
            if (i == list.len() || list[i] == ",") begin
                if (list.substr(start, i - 1) == name)
                    return 1'b1;
                start = i + 1;
            end
        return 1'b0;
    endfunction

    // The check name failed: stop the test (it is not quiet).
    function automatic bit stops(input string name);
        return !listed(name, QUIET);
    endfunction

    // A quiet check failed: print it (the first three times).
    function automatic bit quiet_print();
        n_quiet = n_quiet + 1;
        return n_quiet <= 3;
    endfunction

endpackage

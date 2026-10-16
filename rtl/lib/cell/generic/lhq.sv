/* Latch, transparent while E is 1, TSMC-style cell LHQ.
 *
 */
module LHQ (
    input  wire D,
    input  wire E, // enable
    output reg  Q
);

    // Nonblocking assignment as in IEEE 1800 9.2.2.3 always_latch example
    // (and Cummings, "Nonblocking Assignments in Verilog Synthesis");
    // Lint of Verilator asks for blocking assignment in latches.
    /* verilator lint_off COMBDLY */
    /* verilator lint_off NOLATCH */
    always_latch
        if (E)
            Q <= D;
    /* verilator lint_on NOLATCH */
    /* verilator lint_on COMBDLY */

endmodule

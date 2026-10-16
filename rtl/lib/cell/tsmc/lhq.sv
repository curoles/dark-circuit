/* Latch, transparent while E is 1, cell LHQ mapped to TSMC library cell LHQD1.
 *
 * Needs TSMC standard cell Verilog models; change D1 to use other drive strength.
 * Define DARK_CIRCUIT_FAKE_TSMC to use the fake LHQD1 below instead.
 */
module LHQ (
    input  wire D,
    input  wire E, // enable
    output wire Q
);

    LHQD1 u_lhq(.D(D), .E(E), .Q(Q));

endmodule

`ifdef DARK_CIRCUIT_FAKE_TSMC
module LHQD1 (
    input  wire D,
    input  wire E,
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
`endif

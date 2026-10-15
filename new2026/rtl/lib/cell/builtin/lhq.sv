/* Latch, transparent while E is 1, TSMC-style cell LHQ.
 *
 * Define DARK_CIRCUIT_BUILTIN_UDP to use Verilog user-defined primitive,
 * otherwise always_latch is used.
 */
`ifdef DARK_CIRCUIT_BUILTIN_UDP
primitive UDP_LHQ (Q, D, E);
    output Q;
    reg    Q;
    input  D, E;
    table
    //  D  E  : Q : Q+
        0  1  : ? : 0;
        1  1  : ? : 1;
        ?  0  : ? : -;
        0  x  : 0 : 0;
        1  x  : 1 : 1;
    endtable
endprimitive
`endif

module LHQ (
    input  wire D,
    input  wire E, // enable
    output wire Q
);

`ifdef DARK_CIRCUIT_BUILTIN_UDP
    UDP_LHQ u_lhq(Q, D, E);
`else
    reg q_r;
    // Nonblocking assignment as in IEEE 1800 9.2.2.3 always_latch example
    // (and Cummings, "Nonblocking Assignments in Verilog Synthesis");
    // Lint of Verilator asks for blocking assignment in latches.
    /* verilator lint_off COMBDLY */
    /* verilator lint_off NOLATCH */
    always_latch
        if (E)
            q_r <= D;
    /* verilator lint_on NOLATCH */
    /* verilator lint_on COMBDLY */
    assign Q = q_r;
`endif

endmodule

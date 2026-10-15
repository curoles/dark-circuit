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

    always_latch
        if (E)
            Q <= D;

endmodule
`endif

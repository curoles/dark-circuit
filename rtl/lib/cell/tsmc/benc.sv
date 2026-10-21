/* Booth Encoding cell, cell BENC mapped to TSMC library cell BENCD1.
 *
 * Needs TSMC standard cell Verilog models; change D1 to use other drive strength.
 * Not every TSMC library has BENC, check yours and its pin names.
 * Define DARK_CIRCUIT_FAKE_TSMC to use the fake BENCD1 below instead.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module BENC (
    input  wire M0,
    input  wire M1,
    input  wire M2,
    output wire S,
    output wire A,
    output wire X2
);

    BENCD1 u_benc(.M0(M0), .M1(M1), .M2(M2), .S(S), .A(A), .X2(X2));

endmodule

`ifdef DARK_CIRCUIT_FAKE_TSMC
module BENCD1 (
    input  wire M0,
    input  wire M1,
    input  wire M2,
    output wire S,
    output wire A,
    output wire X2
);

    assign S  = ~(M2 & (~(M1 & M0)));
    assign A  = ~(~M2 & (M1 | M0));
    assign X2 = ~(M1 ^ M0);

endmodule
`endif

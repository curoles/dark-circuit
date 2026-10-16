/* Booth Multiplexer cell, cell BML mapped to TSMC library cell BMLD1.
 *
 * Needs TSMC standard cell Verilog models; change D1 to use other drive strength.
 * Not every TSMC library has BML, check yours and its pin names.
 * Define DARK_CIRCUIT_FAKE_TSMC to use the fake BMLD1 below instead.
 */
module BML (
    input  wire X2,
    input  wire A,
    input  wire S,
    input  wire M0,
    input  wire M1,
    output wire PP
);

    BMLD1 u_bml(.X2(X2), .A(A), .S(S), .M0(M0), .M1(M1), .PP(PP));

endmodule

`ifdef DARK_CIRCUIT_FAKE_TSMC
module BMLD1 (
    input  wire X2,
    input  wire A,
    input  wire S,
    input  wire M0,
    input  wire M1,
    output wire PP
);

    wire m1_sel_n = ~((~A & M1) | (~S & ~M1));
    wire m0_sel_n = ~((~A & M0) | (~S & ~M0));

    assign PP = ~((~X2 & m1_sel_n) | (X2 & m0_sel_n));

endmodule
`endif

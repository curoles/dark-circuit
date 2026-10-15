/* 2-input NOR, cell NR2 mapped to TSMC library cell NR2D1.
 *
 * Needs TSMC standard cell Verilog models; change D1 to use other drive strength.
 * Define DARK_CIRCUIT_FAKE_TSMC to use the fake NR2D1 below instead.
 */
module NR2 (
    input  wire A1,
    input  wire A2,
    output wire ZN
);

    NR2D1 u_nr2(.A1(A1), .A2(A2), .ZN(ZN));

endmodule

`ifdef DARK_CIRCUIT_FAKE_TSMC
module NR2D1 (
    input  wire A1,
    input  wire A2,
    output wire ZN
);

    assign ZN = ~(A1 | A2);

endmodule
`endif

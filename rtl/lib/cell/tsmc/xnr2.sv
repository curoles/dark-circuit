/* 2-input XNOR, cell XNR2 mapped to TSMC library cell XNR2D1.
 *
 * Needs TSMC standard cell Verilog models; change D1 to use other drive strength.
 * Define DARK_CIRCUIT_FAKE_TSMC to use the fake XNR2D1 below instead.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module XNR2 (
    input  wire A1,
    input  wire A2,
    output wire ZN
);

    XNR2D1 u_xnr2(.A1(A1), .A2(A2), .ZN(ZN));

endmodule

`ifdef DARK_CIRCUIT_FAKE_TSMC
module XNR2D1 (
    input  wire A1,
    input  wire A2,
    output wire ZN
);

    assign ZN = ~(A1 ^ A2);

endmodule
`endif

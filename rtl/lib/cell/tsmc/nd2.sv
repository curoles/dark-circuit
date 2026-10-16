/* 2-input NAND, cell ND2 mapped to TSMC library cell ND2D1.
 *
 * Needs TSMC standard cell Verilog models; change D1 to use other drive strength.
 * Define DARK_CIRCUIT_FAKE_TSMC to use the fake ND2D1 below instead.
 */
module ND2 (
    input  wire A1,
    input  wire A2,
    output wire ZN
);

    ND2D1 u_nd2(.A1(A1), .A2(A2), .ZN(ZN));

endmodule

`ifdef DARK_CIRCUIT_FAKE_TSMC
module ND2D1 (
    input  wire A1,
    input  wire A2,
    output wire ZN
);

    assign ZN = ~(A1 & A2);

endmodule
`endif

/* 2-input AND, cell AN2 mapped to TSMC library cell AN2D1.
 *
 * Needs TSMC standard cell Verilog models; change D1 to use other drive strength.
 * Define DARK_CIRCUIT_FAKE_TSMC to use the fake AN2D1 below instead.
 */
module AN2 (
    input  wire A1,
    input  wire A2,
    output wire Z
);

    AN2D1 u_an2(.A1(A1), .A2(A2), .Z(Z));

endmodule

`ifdef DARK_CIRCUIT_FAKE_TSMC
module AN2D1 (
    input  wire A1,
    input  wire A2,
    output wire Z
);

    assign Z = A1 & A2;

endmodule
`endif

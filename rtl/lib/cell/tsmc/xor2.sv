/* 2-input XOR, cell XOR2 mapped to TSMC library cell XOR2D1.
 *
 * Needs TSMC standard cell Verilog models; change D1 to use other drive strength.
 * Define DARK_CIRCUIT_FAKE_TSMC to use the fake XOR2D1 below instead.
 */
module XOR2 (
    input  wire A1,
    input  wire A2,
    output wire Z
);

    XOR2D1 u_xor2(.A1(A1), .A2(A2), .Z(Z));

endmodule

`ifdef DARK_CIRCUIT_FAKE_TSMC
module XOR2D1 (
    input  wire A1,
    input  wire A2,
    output wire Z
);

    assign Z = A1 ^ A2;

endmodule
`endif

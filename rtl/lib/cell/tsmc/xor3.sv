/* 3-input XOR, cell XOR3 mapped to TSMC library cell XOR3D1.
 *
 * Needs TSMC standard cell Verilog models; change D1 to use other drive strength.
 * Define DARK_CIRCUIT_FAKE_TSMC to use the fake XOR3D1 below instead.
 */
module XOR3 (
    input  wire A1,
    input  wire A2,
    input  wire A3,
    output wire Z
);

    XOR3D1 u_xor3(.A1(A1), .A2(A2), .A3(A3), .Z(Z));

endmodule

`ifdef DARK_CIRCUIT_FAKE_TSMC
module XOR3D1 (
    input  wire A1,
    input  wire A2,
    input  wire A3,
    output wire Z
);

    assign Z = A1 ^ A2 ^ A3;

endmodule
`endif

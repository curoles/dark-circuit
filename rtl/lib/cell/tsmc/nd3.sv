/* 3-input NAND, cell ND3 mapped to TSMC library cell ND3D1.
 *
 * Needs TSMC standard cell Verilog models; change D1 to use other drive strength.
 * Define DARK_CIRCUIT_FAKE_TSMC to use the fake ND3D1 below instead.
 */
module ND3 (
    input  wire A1,
    input  wire A2,
    input  wire A3,
    output wire ZN
);

    ND3D1 u_nd3(.A1(A1), .A2(A2), .A3(A3), .ZN(ZN));

endmodule

`ifdef DARK_CIRCUIT_FAKE_TSMC
module ND3D1 (
    input  wire A1,
    input  wire A2,
    input  wire A3,
    output wire ZN
);

    assign ZN = ~(A1 & A2 & A3);

endmodule
`endif

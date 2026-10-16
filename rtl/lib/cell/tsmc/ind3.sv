/* 3-input NAND with 1 inverted input, cell IND3 mapped to TSMC library cell IND3D1.
 *
 * Needs TSMC standard cell Verilog models; change D1 to use other drive strength.
 * Define DARK_CIRCUIT_FAKE_TSMC to use the fake IND3D1 below instead.
 */
module IND3 (
    input  wire A1, // inverted
    input  wire B1,
    input  wire B2,
    output wire ZN
);

    IND3D1 u_ind3(.A1(A1), .B1(B1), .B2(B2), .ZN(ZN));

endmodule

`ifdef DARK_CIRCUIT_FAKE_TSMC
module IND3D1 (
    input  wire A1,
    input  wire B1,
    input  wire B2,
    output wire ZN
);

    assign ZN = ~(~A1 & B1 & B2);

endmodule
`endif

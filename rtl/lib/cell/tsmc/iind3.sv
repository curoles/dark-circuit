/* 3-input NAND with 2 inverted inputs, cell IIND3 mapped to TSMC library cell IIND3D1.
 *
 * Needs TSMC standard cell Verilog models; change D1 to use other drive strength.
 * Not every TSMC library has IIND3, check yours.
 * Define DARK_CIRCUIT_FAKE_TSMC to use the fake IIND3D1 below instead.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module IIND3 (
    input  wire A1, // inverted
    input  wire A2, // inverted
    input  wire B1,
    output wire ZN
);

    IIND3D1 u_iind3(.A1(A1), .A2(A2), .B1(B1), .ZN(ZN));

endmodule

`ifdef DARK_CIRCUIT_FAKE_TSMC
module IIND3D1 (
    input  wire A1,
    input  wire A2,
    input  wire B1,
    output wire ZN
);

    assign ZN = ~(~A1 & ~A2 & B1);

endmodule
`endif

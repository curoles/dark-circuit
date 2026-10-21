/* 2-input NAND with 1 inverted input, cell IND2 mapped to TSMC library cell IND2D1.
 *
 * Needs TSMC standard cell Verilog models; change D1 to use other drive strength.
 * Define DARK_CIRCUIT_FAKE_TSMC to use the fake IND2D1 below instead.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module IND2 (
    input  wire A1, // inverted
    input  wire B1,
    output wire ZN
);

    IND2D1 u_ind2(.A1(A1), .B1(B1), .ZN(ZN));

endmodule

`ifdef DARK_CIRCUIT_FAKE_TSMC
module IND2D1 (
    input  wire A1,
    input  wire B1,
    output wire ZN
);

    assign ZN = ~(~A1 & B1);

endmodule
`endif

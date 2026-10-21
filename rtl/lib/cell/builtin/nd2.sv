/* 2-input NAND with Verilog primitive `nand`, TSMC-style cell ND2.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module ND2 (
    input  wire A1,
    input  wire A2,
    output wire ZN
);

    nand /*(strength)*/ /*#(3 delays)*/ u_nand(ZN, A1, A2);

endmodule

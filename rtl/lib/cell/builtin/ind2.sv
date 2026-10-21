/* 2-input NAND with 1 inverted input, Verilog primitives `not` and `nand`,
 * TSMC-style cell IND2.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module IND2 (
    input  wire A1, // inverted
    input  wire B1,
    output wire ZN
);

    wire a1_n;

    not  u_not(a1_n, A1);
    nand u_nand(ZN, a1_n, B1);

endmodule

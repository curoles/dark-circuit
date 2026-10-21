/* 3-input NAND with 1 inverted input, Verilog primitives `not` and `nand`,
 * TSMC-style cell IND3.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module IND3 (
    input  wire A1, // inverted
    input  wire B1,
    input  wire B2,
    output wire ZN
);

    wire a1_n;

    not  u_not(a1_n, A1);
    nand u_nand(ZN, a1_n, B1, B2);

endmodule

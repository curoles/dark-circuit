/* 3-input NAND with 2 inverted inputs, Verilog primitives `not` and `nand`,
 * TSMC-style cell IIND3.
 *
 */
module IIND3 (
    input  wire A1, // inverted
    input  wire A2, // inverted
    input  wire B1,
    output wire ZN
);

    wire a1_n, a2_n;

    not  u_not_1(a1_n, A1);
    not  u_not_2(a2_n, A2);
    nand u_nand(ZN, a1_n, a2_n, B1);

endmodule

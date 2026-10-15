/* 3-input NAND with Verilog primitive `nand`, TSMC-style cell ND3.
 *
 */
module ND3 (
    input  wire A1,
    input  wire A2,
    input  wire A3,
    output wire ZN
);

    nand /*(strength)*/ /*#(3 delays)*/ u_nand(ZN, A1, A2, A3);

endmodule

/* 2-input NAND, TSMC-style cell ND2.
 *
 */
module ND2 (
    input  wire A1,
    input  wire A2,
    output wire ZN
);

    assign ZN = ~(A1 & A2);

endmodule

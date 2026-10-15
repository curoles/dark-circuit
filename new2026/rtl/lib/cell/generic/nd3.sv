/* 3-input NAND, TSMC-style cell ND3.
 *
 */
module ND3 (
    input  wire A1,
    input  wire A2,
    input  wire A3,
    output wire ZN
);

    assign ZN = ~(A1 & A2 & A3);

endmodule

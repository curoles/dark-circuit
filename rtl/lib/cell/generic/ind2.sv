/* 2-input NAND with 1 inverted input, TSMC-style cell IND2.
 *
 */
module IND2 (
    input  wire A1, // inverted
    input  wire B1,
    output wire ZN
);

    assign ZN = ~(~A1 & B1);

endmodule

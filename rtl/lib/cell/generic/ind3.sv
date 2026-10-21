/* 3-input NAND with 1 inverted input, TSMC-style cell IND3.
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

    assign ZN = ~(~A1 & B1 & B2);

endmodule

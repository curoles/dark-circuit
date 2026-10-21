/* 2-input NAND with 1 inverted input, TSMC-style cell IND2.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module IND2 (
    input  wire A1, // inverted
    input  wire B1,
    output wire ZN
);

    assign ZN = ~(~A1 & B1);

endmodule

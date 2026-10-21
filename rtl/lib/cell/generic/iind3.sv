/* 3-input NAND with 2 inverted inputs, TSMC-style cell IIND3.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module IIND3 (
    input  wire A1, // inverted
    input  wire A2, // inverted
    input  wire B1,
    output wire ZN
);

    assign ZN = ~(~A1 & ~A2 & B1);

endmodule

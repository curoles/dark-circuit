/* 3-input Majority, TSMC-style cell MAJ3.
 *
 * Z is 1 when at least 2 of 3 inputs are 1, it is carry of full adder.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module MAJ3 (
    input  wire A1,
    input  wire A2,
    input  wire A3,
    output wire Z
);

    assign Z = (A1 & A2) | (A1 & A3) | (A2 & A3);

endmodule

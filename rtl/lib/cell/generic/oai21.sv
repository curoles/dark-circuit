/* OR-AND-Invert, 2-input OR feeding NAND with 1 input, TSMC-style cell OAI21.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module OAI21 (
    input  wire A1, // to be OR-ed with A2
    input  wire A2, // to be OR-ed with A1
    input  wire B,
    output wire ZN
);

    assign ZN = ~((A1 | A2) & B);

endmodule

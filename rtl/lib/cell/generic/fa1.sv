/* Full Adder, TSMC-style cell FA1.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module FA1 (
    input  wire A,
    input  wire B,
    input  wire CI, // carry in
    output wire S,  // sum
    output wire CO  // carry out
);

    assign S  = A ^ B ^ CI;
    assign CO = (A & B) | (CI & (A | B));

endmodule

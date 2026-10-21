/* AND-OR-Invert, 3-input AND feeding NOR with 1 input, TSMC-style cell AOI31.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module AOI31 (
    input  wire A1,
    input  wire A2,
    input  wire A3,
    input  wire B,
    output wire ZN
);

    assign ZN = ~((A1 & A2 & A3) | B);

endmodule

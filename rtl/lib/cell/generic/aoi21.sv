/* AND-OR-Invert, 2-input AND feeding NOR with 1 input, TSMC-style cell AOI21.
 *
 */
module AOI21 (
    input  wire A1, // to be AND-ed with A2
    input  wire A2, // to be AND-ed with A1
    input  wire B,
    output wire ZN
);

    assign ZN = ~((A1 & A2) | B);

endmodule

/* 2-input NOR, TSMC-style cell NR2.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module NR2 (
    input  wire A1,
    input  wire A2,
    output wire ZN
);

    assign ZN = ~(A1 | A2);

endmodule

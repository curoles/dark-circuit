/* 3-input NOR, TSMC-style cell NR3.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module NR3 (
    input  wire A1,
    input  wire A2,
    input  wire A3,
    output wire ZN
);

    assign ZN = ~(A1 | A2 | A3);

endmodule

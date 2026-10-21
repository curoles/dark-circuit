/* 3-input OR, TSMC-style cell OR3.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module OR3 (
    input  wire A1,
    input  wire A2,
    input  wire A3,
    output wire Z
);

    assign Z = A1 | A2 | A3;

endmodule

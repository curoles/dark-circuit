/* 2-input OR with Verilog primitive `or`, TSMC-style cell OR2.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module OR2 (
    input  wire A1,
    input  wire A2,
    output wire Z
);

    or /*(strength)*/ /*#(3 delays)*/ u_or(Z, A1, A2);

endmodule

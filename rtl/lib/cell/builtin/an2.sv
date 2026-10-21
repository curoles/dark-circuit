/* 2-input AND with Verilog primitive `and`, TSMC-style cell AN2.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module AN2 (
    input  wire A1,
    input  wire A2,
    output wire Z
);

    and /*(strength)*/ /*#(3 delays)*/ u_and(Z, A1, A2);

endmodule

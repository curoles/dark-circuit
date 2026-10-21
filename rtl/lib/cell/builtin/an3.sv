/* 3-input AND with Verilog primitive `and`, TSMC-style cell AN3.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module AN3 (
    input  wire A1,
    input  wire A2,
    input  wire A3,
    output wire Z
);

    and /*(strength)*/ /*#(3 delays)*/ u_and(Z, A1, A2, A3);

endmodule

/* Buffer with Verilog primitive `buf`, TSMC-style cell BUF.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module BUF (
    input  wire I,
    output wire Z
);

    buf /*(strength)*/ /*#(2 delays)*/ u_buf(Z, I);

endmodule

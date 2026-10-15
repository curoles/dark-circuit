/* Buffer with Verilog primitive `buf`, TSMC-style cell BUF.
 *
 */
module BUF (
    input  wire I,
    output wire Z
);

    buf /*(strength)*/ /*#(2 delays)*/ u_buf(Z, I);

endmodule

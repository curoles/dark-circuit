/* 2-input XNOR with Verilog primitive `xnor`, TSMC-style cell XNR2.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module XNR2 (
    input  wire A1,
    input  wire A2,
    output wire ZN
);

    xnor /*(strength)*/ /*#(3 delays)*/ u_xnor(ZN, A1, A2);

endmodule

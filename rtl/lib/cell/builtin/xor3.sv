/* 3-input XOR with Verilog primitive `xor`, TSMC-style cell XOR3.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module XOR3 (
    input  wire A1,
    input  wire A2,
    input  wire A3,
    output wire Z
);

    xor /*(strength)*/ /*#(3 delays)*/ u_xor(Z, A1, A2, A3);

endmodule

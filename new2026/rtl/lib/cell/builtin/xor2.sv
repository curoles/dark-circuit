/* 2-input XOR with Verilog primitive `xor`, TSMC-style cell XOR2.
 *
 */
module XOR2 (
    input  wire A1,
    input  wire A2,
    output wire Z
);

    xor /*(strength)*/ /*#(3 delays)*/ u_xor(Z, A1, A2);

endmodule

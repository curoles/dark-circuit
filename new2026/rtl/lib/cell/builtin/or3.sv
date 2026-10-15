/* 3-input OR with Verilog primitive `or`, TSMC-style cell OR3.
 *
 */
module OR3 (
    input  wire A1,
    input  wire A2,
    input  wire A3,
    output wire Z
);

    or /*(strength)*/ /*#(3 delays)*/ u_or(Z, A1, A2, A3);

endmodule

/* 2-input NOR with Verilog primitive `nor`, TSMC-style cell NR2.
 *
 */
module NR2 (
    input  wire A1,
    input  wire A2,
    output wire ZN
);

    nor /*(strength)*/ /*#(3 delays)*/ u_nor(ZN, A1, A2);

endmodule

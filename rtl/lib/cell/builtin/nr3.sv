/* 3-input NOR with Verilog primitive `nor`, TSMC-style cell NR3.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module NR3 (
    input  wire A1,
    input  wire A2,
    input  wire A3,
    output wire ZN
);

    nor /*(strength)*/ /*#(3 delays)*/ u_nor(ZN, A1, A2, A3);

endmodule

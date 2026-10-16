/* Inverting 2:1 Multiplexer, TSMC-style cell MUX2N.
 *
 */
module MUX2N (
    input  wire I0,  // inverted to ZN when S is 0
    input  wire I1,  // inverted to ZN when S is 1
    input  wire S,
    output wire ZN
);

    assign ZN = ~(S ? I1 : I0);

endmodule

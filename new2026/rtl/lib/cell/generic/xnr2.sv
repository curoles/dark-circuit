/* 2-input XNOR, TSMC-style cell XNR2.
 *
 */
module XNR2 (
    input  wire A1,
    input  wire A2,
    output wire ZN
);

    assign ZN = ~(A1 ^ A2);

endmodule

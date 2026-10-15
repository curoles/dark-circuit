/* 2-input AND, TSMC-style cell AN2.
 *
 */
module AN2 (
    input  wire A1,
    input  wire A2,
    output wire Z
);

    assign Z = A1 & A2;

endmodule

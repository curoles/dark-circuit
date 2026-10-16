/* 3-input AND, TSMC-style cell AN3.
 *
 */
module AN3 (
    input  wire A1,
    input  wire A2,
    input  wire A3,
    output wire Z
);

    assign Z = A1 & A2 & A3;

endmodule

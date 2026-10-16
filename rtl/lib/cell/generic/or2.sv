/* 2-input OR, TSMC-style cell OR2.
 *
 */
module OR2 (
    input  wire A1,
    input  wire A2,
    output wire Z
);

    assign Z = A1 | A2;

endmodule

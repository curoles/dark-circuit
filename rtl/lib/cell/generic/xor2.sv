/* 2-input XOR, TSMC-style cell XOR2.
 *
 */
module XOR2 (
    input  wire A1,
    input  wire A2,
    output wire Z
);

    assign Z = A1 ^ A2;

endmodule

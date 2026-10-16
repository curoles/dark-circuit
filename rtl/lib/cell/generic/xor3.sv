/* 3-input XOR, TSMC-style cell XOR3.
 *
 */
module XOR3 (
    input  wire A1,
    input  wire A2,
    input  wire A3,
    output wire Z
);

    assign Z = A1 ^ A2 ^ A3;

endmodule

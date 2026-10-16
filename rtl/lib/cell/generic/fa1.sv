/* Full Adder, TSMC-style cell FA1.
 *
 */
module FA1 (
    input  wire A,
    input  wire B,
    input  wire CI, // carry in
    output wire S,  // sum
    output wire CO  // carry out
);

    assign S  = A ^ B ^ CI;
    assign CO = (A & B) | (CI & (A | B));

endmodule

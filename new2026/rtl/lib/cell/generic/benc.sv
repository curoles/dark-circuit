/* Booth Encoding cell, TSMC-style cell BENC.
 *
 * The M2, M1, and M0 inputs are the three bits from the multiplier
 * that are used to derive the Partial Product.
 */
module BENC (
    input  wire M0,
    input  wire M1,
    input  wire M2,
    output wire S,
    output wire A,
    output wire X2
);

    assign S  = ~(M2 & (~(M1 & M0)));

    assign A  = ~(~M2 & (M1 | M0));

    assign X2 = ~(M1 ^ M0);

endmodule

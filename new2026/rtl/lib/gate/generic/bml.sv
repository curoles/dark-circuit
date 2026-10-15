/* Booth Multiplexer.
 *
 * Takes in two bits of the multiplicand at a time and generates the partial product
 * using other inputs that come in from the booth encoder Benc.
 *
 */
module Bml #(
    parameter WIDTH = 1
)(
    input  wire [WIDTH-1:0] X2,
    input  wire [WIDTH-1:0] A,
    input  wire [WIDTH-1:0] S,
    input  wire [WIDTH-1:0] M0,
    input  wire [WIDTH-1:0] M1,
    output wire [WIDTH-1:0] PP
);

    wire [WIDTH-1:0] m1_sel_n;
    wire [WIDTH-1:0] m0_sel_n;

    assign m1_sel_n = ~((~A & M1) | (~S & ~M1));
    assign m0_sel_n = ~((~A & M0) | (~S & ~M0));

    assign PP = ~((~X2 & m1_sel_n) | (X2 & m0_sel_n));

endmodule

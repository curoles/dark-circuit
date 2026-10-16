/* Half Adder, TSMC-style cell HA1.
 *
 */
module HA1 (
    input  wire A,
    input  wire B,
    output wire S,  // sum
    output wire CO  // carry out
);

    assign S  = A ^ B;
    assign CO = A & B;

endmodule

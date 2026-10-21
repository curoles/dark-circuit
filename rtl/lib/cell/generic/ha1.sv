/* Half Adder, TSMC-style cell HA1.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
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

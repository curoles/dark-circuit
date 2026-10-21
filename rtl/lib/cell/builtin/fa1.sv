/* Full Adder with Verilog primitives `xor`, `and` and `or`, TSMC-style cell FA1.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module FA1 (
    input  wire A,
    input  wire B,
    input  wire CI, // carry in
    output wire S,  // sum
    output wire CO  // carry out
);

    wire ab_and, ab_or, c_ab;

    xor u_xor(S, A, B, CI);

    and u_and_ab(ab_and, A, B);
    or  u_or_ab(ab_or, A, B);
    and u_and_c(c_ab, CI, ab_or);
    or  u_or_co(CO, ab_and, c_ab);

endmodule

/* Half Adder with Verilog primitives `xor` and `and`, TSMC-style cell HA1.
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

    xor u_xor(S, A, B);
    and u_and(CO, A, B);

endmodule

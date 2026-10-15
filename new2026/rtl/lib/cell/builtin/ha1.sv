/* Half Adder with Verilog primitives `xor` and `and`, TSMC-style cell HA1.
 *
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

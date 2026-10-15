/* OR-AND-Invert with Verilog primitives `or` and `nand`, TSMC-style cell OAI22.
 *
 */
module OAI22 (
    input  wire A1,
    input  wire A2,
    input  wire B1,
    input  wire B2,
    output wire ZN
);

    wire a12, b12;

    or   u_or_a(a12, A1, A2);
    or   u_or_b(b12, B1, B2);
    nand u_nand(ZN, a12, b12);

endmodule

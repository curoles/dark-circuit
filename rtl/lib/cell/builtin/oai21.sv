/* OR-AND-Invert with Verilog primitives `or` and `nand`, TSMC-style cell OAI21.
 *
 */
module OAI21 (
    input  wire A1,
    input  wire A2,
    input  wire B,
    output wire ZN
);

    wire a12;

    or   u_or(a12, A1, A2);
    nand u_nand(ZN, a12, B);

endmodule

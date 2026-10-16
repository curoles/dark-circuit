/* AND-OR-Invert with Verilog primitives `and` and `nor`, TSMC-style cell AOI22.
 *
 */
module AOI22 (
    input  wire A1,
    input  wire A2,
    input  wire B1,
    input  wire B2,
    output wire ZN
);

    wire a12, b12;

    and u_and_a(a12, A1, A2);
    and u_and_b(b12, B1, B2);
    nor u_nor(ZN, a12, b12);

endmodule

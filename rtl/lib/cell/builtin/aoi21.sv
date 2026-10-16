/* AND-OR-Invert with Verilog primitives `and` and `nor`, TSMC-style cell AOI21.
 *
 */
module AOI21 (
    input  wire A1,
    input  wire A2,
    input  wire B,
    output wire ZN
);

    wire a12;

    and u_and(a12, A1, A2);
    nor u_nor(ZN, a12, B);

endmodule

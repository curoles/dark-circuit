/* AND-OR-Invert with Verilog primitives `and` and `nor`, TSMC-style cell AOI31.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module AOI31 (
    input  wire A1,
    input  wire A2,
    input  wire A3,
    input  wire B,
    output wire ZN
);

    wire a123;

    and u_and(a123, A1, A2, A3);
    nor u_nor(ZN, a123, B);

endmodule

/* Inverting 2:1 Multiplexer made with Verilog primitives `nand`, `and` and `not`,
 * TSMC-style cell MUX2N.
 *
 */
module MUX2N (
    input  wire I0,  // inverted to ZN when S is 0
    input  wire I1,  // inverted to ZN when S is 1
    input  wire S,
    output wire ZN
);

    wire s_n, o1, o0;

    not  u_not_sel(s_n, S);
    nand u_nand_1(o1, I1, S);
    nand u_nand_0(o0, I0, s_n);
    and  u_and_out(ZN, o1, o0);

endmodule

/* 3-input Majority with Verilog primitives `and` and `or`, TSMC-style cell MAJ3.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module MAJ3 (
    input  wire A1,
    input  wire A2,
    input  wire A3,
    output wire Z
);

    wire a12, a13, a23;

    and u_and_12(a12, A1, A2);
    and u_and_13(a13, A1, A3);
    and u_and_23(a23, A2, A3);
    or  u_or(Z, a12, a13, a23);

endmodule

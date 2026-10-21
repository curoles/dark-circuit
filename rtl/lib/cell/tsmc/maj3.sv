/* 3-input Majority, cell MAJ3 mapped to TSMC library cell MAOI222D1 and cell INV.
 *
 * MAOI222D1 is inverting majority, ZN = ~((A & B) | (A & C) | (B & C)).
 * Needs TSMC standard cell Verilog models; change D1 to use other drive strength.
 * Check that your library has MAOI222 and its pin names,
 * or map to non-inverting majority cell if your library has one.
 * Define DARK_CIRCUIT_FAKE_TSMC to use the fake MAOI222D1 below instead.
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
    wire z_n;

    MAOI222D1 u_maoi222(.A(A1), .B(A2), .C(A3), .ZN(z_n));
    INV       u_inv(.I(z_n), .ZN(Z));

endmodule

`ifdef DARK_CIRCUIT_FAKE_TSMC
module MAOI222D1 (
    input  wire A,
    input  wire B,
    input  wire C,
    output wire ZN
);

    assign ZN = ~((A & B) | (A & C) | (B & C));

endmodule
`endif

/* 2-input OR, cell OR2 mapped to TSMC library cell OR2D1.
 *
 * Needs TSMC standard cell Verilog models; change D1 to use other drive strength.
 * Define DARK_CIRCUIT_FAKE_TSMC to use the fake OR2D1 below instead.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module OR2 (
    input  wire A1,
    input  wire A2,
    output wire Z
);

    OR2D1 u_or2(.A1(A1), .A2(A2), .Z(Z));

endmodule

`ifdef DARK_CIRCUIT_FAKE_TSMC
module OR2D1 (
    input  wire A1,
    input  wire A2,
    output wire Z
);

    assign Z = A1 | A2;

endmodule
`endif

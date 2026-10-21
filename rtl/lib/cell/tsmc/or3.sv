/* 3-input OR, cell OR3 mapped to TSMC library cell OR3D1.
 *
 * Needs TSMC standard cell Verilog models; change D1 to use other drive strength.
 * Define DARK_CIRCUIT_FAKE_TSMC to use the fake OR3D1 below instead.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module OR3 (
    input  wire A1,
    input  wire A2,
    input  wire A3,
    output wire Z
);

    OR3D1 u_or3(.A1(A1), .A2(A2), .A3(A3), .Z(Z));

endmodule

`ifdef DARK_CIRCUIT_FAKE_TSMC
module OR3D1 (
    input  wire A1,
    input  wire A2,
    input  wire A3,
    output wire Z
);

    assign Z = A1 | A2 | A3;

endmodule
`endif

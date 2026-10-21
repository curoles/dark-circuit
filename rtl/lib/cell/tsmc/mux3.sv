/* 3:1 Multiplexer, cell MUX3 mapped to TSMC library cell MUX3D1.
 *
 * Needs TSMC standard cell Verilog models; change D1 to use other drive strength.
 * Expects S1 to select I2 regardless of S0, check your library.
 * Define DARK_CIRCUIT_FAKE_TSMC to use the fake MUX3D1 below instead.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module MUX3 (
    input  wire I0,
    input  wire I1,
    input  wire I2,
    input  wire S0,
    input  wire S1,
    output wire Z
);

    MUX3D1 u_mux3(.I0(I0), .I1(I1), .I2(I2), .S0(S0), .S1(S1), .Z(Z));

endmodule

`ifdef DARK_CIRCUIT_FAKE_TSMC
module MUX3D1 (
    input  wire I0,
    input  wire I1,
    input  wire I2,
    input  wire S0,
    input  wire S1,
    output wire Z
);

    assign Z = S1 ? I2 : (S0 ? I1 : I0);

endmodule
`endif

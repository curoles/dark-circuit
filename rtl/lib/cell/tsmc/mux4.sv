/* 4:1 Multiplexer, cell MUX4 mapped to TSMC library cell MUX4D1.
 *
 * Needs TSMC standard cell Verilog models; change D1 to use other drive strength.
 * Define DARK_CIRCUIT_FAKE_TSMC to use the fake MUX4D1 below instead.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module MUX4 (
    input  wire I0,
    input  wire I1,
    input  wire I2,
    input  wire I3,
    input  wire S0,
    input  wire S1,
    output wire Z
);

    MUX4D1 u_mux4(.I0(I0), .I1(I1), .I2(I2), .I3(I3), .S0(S0), .S1(S1), .Z(Z));

endmodule

`ifdef DARK_CIRCUIT_FAKE_TSMC
module MUX4D1 (
    input  wire I0,
    input  wire I1,
    input  wire I2,
    input  wire I3,
    input  wire S0,
    input  wire S1,
    output wire Z
);

    assign Z = S1 ? (S0 ? I3 : I2) : (S0 ? I1 : I0);

endmodule
`endif

/* 2:1 Multiplexer, cell MUX2 mapped to TSMC library cell MUX2D1.
 *
 * Needs TSMC standard cell Verilog models; change D1 to use other drive strength.
 * Define DARK_CIRCUIT_FAKE_TSMC to use the fake MUX2D1 below instead.
 */
module MUX2 (
    input  wire I0,  // selected when S is 0
    input  wire I1,  // selected when S is 1
    input  wire S,
    output wire Z
);

    MUX2D1 u_mux2(.I0(I0), .I1(I1), .S(S), .Z(Z));

endmodule

`ifdef DARK_CIRCUIT_FAKE_TSMC
module MUX2D1 (
    input  wire I0,
    input  wire I1,
    input  wire S,
    output wire Z
);

    assign Z = S ? I1 : I0;

endmodule
`endif

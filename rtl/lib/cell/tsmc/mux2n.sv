/* Inverting 2:1 Multiplexer, cell MUX2N mapped to TSMC library cell MUX2ND1.
 *
 * Needs TSMC standard cell Verilog models; change D1 to use other drive strength.
 * Define DARK_CIRCUIT_FAKE_TSMC to use the fake MUX2ND1 below instead.
 */
module MUX2N (
    input  wire I0,  // inverted to ZN when S is 0
    input  wire I1,  // inverted to ZN when S is 1
    input  wire S,
    output wire ZN
);

    MUX2ND1 u_mux2n(.I0(I0), .I1(I1), .S(S), .ZN(ZN));

endmodule

`ifdef DARK_CIRCUIT_FAKE_TSMC
module MUX2ND1 (
    input  wire I0,
    input  wire I1,
    input  wire S,
    output wire ZN
);

    assign ZN = ~(S ? I1 : I0);

endmodule
`endif

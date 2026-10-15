/* Complex gate And-Or-Invertor, cell AOI22 mapped to TSMC library cell AOI22D1.
 *
 * Needs TSMC standard cell Verilog models; change D1 to use other drive strength.
 * Define DARK_CIRCUIT_FAKE_TSMC to use the fake AOI22D1 below instead.
 */
module AOI22 (
    input  wire A1, // to be AND-ed with A2
    input  wire A2, // to be AND-ed with A1
    input  wire B1, // to be AND-ed with B2
    input  wire B2, // to be AND-ed with B1
    output wire ZN  // NOR the results of two ANDs
);

    AOI22D1 u_aoi22(.A1(A1), .A2(A2), .B1(B1), .B2(B2), .ZN(ZN));

endmodule

`ifdef DARK_CIRCUIT_FAKE_TSMC
module AOI22D1 (
    input  wire A1,
    input  wire A2,
    input  wire B1,
    input  wire B2,
    output wire ZN
);

    assign ZN = ~((A1 & A2) | (B1 & B2));

endmodule
`endif

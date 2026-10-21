/* AND-OR-Invert, cell AOI21 mapped to TSMC library cell AOI21D1.
 *
 * Needs TSMC standard cell Verilog models; change D1 to use other drive strength.
 * Define DARK_CIRCUIT_FAKE_TSMC to use the fake AOI21D1 below instead.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module AOI21 (
    input  wire A1,
    input  wire A2,
    input  wire B,
    output wire ZN
);

    AOI21D1 u_aoi21(.A1(A1), .A2(A2), .B(B), .ZN(ZN));

endmodule

`ifdef DARK_CIRCUIT_FAKE_TSMC
module AOI21D1 (
    input  wire A1,
    input  wire A2,
    input  wire B,
    output wire ZN
);

    assign ZN = ~((A1 & A2) | B);

endmodule
`endif

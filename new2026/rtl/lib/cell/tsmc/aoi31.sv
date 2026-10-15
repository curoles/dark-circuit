/* AND-OR-Invert, cell AOI31 mapped to TSMC library cell AOI31D1.
 *
 * Needs TSMC standard cell Verilog models; change D1 to use other drive strength.
 * Define DARK_CIRCUIT_FAKE_TSMC to use the fake AOI31D1 below instead.
 */
module AOI31 (
    input  wire A1,
    input  wire A2,
    input  wire A3,
    input  wire B,
    output wire ZN
);

    AOI31D1 u_aoi31(.A1(A1), .A2(A2), .A3(A3), .B(B), .ZN(ZN));

endmodule

`ifdef DARK_CIRCUIT_FAKE_TSMC
module AOI31D1 (
    input  wire A1,
    input  wire A2,
    input  wire A3,
    input  wire B,
    output wire ZN
);

    assign ZN = ~((A1 & A2 & A3) | B);

endmodule
`endif

/* Full Adder, cell FA1 mapped to TSMC library cell FA1D1.
 *
 * Needs TSMC standard cell Verilog models; change D1 to use other drive strength.
 * Define DARK_CIRCUIT_FAKE_TSMC to use the fake FA1D1 below instead.
 */
module FA1 (
    input  wire A,
    input  wire B,
    input  wire CI, // carry in
    output wire S,  // sum
    output wire CO  // carry out
);

    FA1D1 u_fa1(.A(A), .B(B), .CI(CI), .S(S), .CO(CO));

endmodule

`ifdef DARK_CIRCUIT_FAKE_TSMC
module FA1D1 (
    input  wire A,
    input  wire B,
    input  wire CI,
    output wire S,
    output wire CO
);

    assign S  = A ^ B ^ CI;
    assign CO = (A & B) | (CI & (A | B));

endmodule
`endif

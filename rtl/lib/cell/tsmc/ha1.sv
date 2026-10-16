/* Half Adder, cell HA1 mapped to TSMC library cell HA1D1.
 *
 * Needs TSMC standard cell Verilog models; change D1 to use other drive strength.
 * Define DARK_CIRCUIT_FAKE_TSMC to use the fake HA1D1 below instead.
 */
module HA1 (
    input  wire A,
    input  wire B,
    output wire S,  // sum
    output wire CO  // carry out
);

    HA1D1 u_ha1(.A(A), .B(B), .S(S), .CO(CO));

endmodule

`ifdef DARK_CIRCUIT_FAKE_TSMC
module HA1D1 (
    input  wire A,
    input  wire B,
    output wire S,
    output wire CO
);

    assign S  = A ^ B;
    assign CO = A & B;

endmodule
`endif

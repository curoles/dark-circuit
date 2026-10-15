/* Buffer, cell BUF mapped to TSMC library cell BUFFD1.
 *
 * Needs TSMC standard cell Verilog models; change D1 to use other drive strength.
 * Define DARK_CIRCUIT_FAKE_TSMC to use the fake BUFFD1 below instead.
 */
module BUF (
    input  wire I,
    output wire Z
);

    BUFFD1 u_buf(.I(I), .Z(Z));

endmodule

`ifdef DARK_CIRCUIT_FAKE_TSMC
module BUFFD1 (
    input  wire I,
    output wire Z
);

    assign Z = I;

endmodule
`endif

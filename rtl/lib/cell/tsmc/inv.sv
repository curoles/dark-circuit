/* Inverter, cell INV mapped to TSMC library cell INVD1.
 *
 * Needs TSMC standard cell Verilog models; change D1 to use other drive strength.
 * Define DARK_CIRCUIT_FAKE_TSMC to use the fake INVD1 below instead.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module INV (
    input  wire I,  // to be inverted
    output wire ZN  // ZN is inverted I
);

    INVD1 u_inv(.I(I), .ZN(ZN));

endmodule

`ifdef DARK_CIRCUIT_FAKE_TSMC
module INVD1 (
    input  wire I,
    output wire ZN
);

    assign ZN = ~I;

endmodule
`endif

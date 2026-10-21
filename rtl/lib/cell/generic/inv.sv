/* Inverter, TSMC-style cell INV.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module INV (
    input  wire I,  // to be inverted
    output wire ZN  // ZN is inverted I
);

    assign ZN = ~I;

endmodule

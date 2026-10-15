/* Inverter, TSMC-style cell INV.
 *
 */
module INV (
    input  wire I,  // to be inverted
    output wire ZN  // ZN is inverted I
);

    assign ZN = ~I;

endmodule

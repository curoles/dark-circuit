/* Inverter.
 *
 */
module INV (
    input  wire in,  // to be inverted
    output wire out  // out is inverted in
);

    assign out = ~in;

endmodule

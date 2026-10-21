/* Inverter with Verilog primitive `not`, TSMC-style cell INV.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module INV (
    input  wire I,  // to be inverted
    output wire ZN  // ZN is inverted I
);

    not /*(strength)*/ /*#(2 delays)*/ u_not(ZN, I);

endmodule

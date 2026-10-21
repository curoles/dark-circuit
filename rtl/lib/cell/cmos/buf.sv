/* CMOS Buffer, TSMC-style cell BUF.
 *
 * Two inverters.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module BUF (
    input  wire I,
    output wire Z
);
    wire i_n;
    INV u_inv_1(.I(I), .ZN(i_n));
    INV u_inv_2(.I(i_n), .ZN(Z));

endmodule

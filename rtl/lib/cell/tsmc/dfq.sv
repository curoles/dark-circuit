/* Rising edge D Flip Flop, cell DFQ mapped to TSMC library cell DFQD1.
 *
 * Needs TSMC standard cell Verilog models; change D1 to use other drive strength.
 * Define DARK_CIRCUIT_FAKE_TSMC to use the fake DFQD1 below instead.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module DFQ (
    input  wire D,
    input  wire CP, // clock
    output wire Q
);

    DFQD1 u_dfq(.D(D), .CP(CP), .Q(Q));

endmodule

`ifdef DARK_CIRCUIT_FAKE_TSMC
module DFQD1 (
    input  wire D,
    input  wire CP,
    output reg  Q
);

    always_ff @(posedge CP)
        Q <= D;

endmodule
`endif

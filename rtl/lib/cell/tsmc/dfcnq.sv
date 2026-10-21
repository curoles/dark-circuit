/* Rising edge D Flip Flop with asynchronous clear,
 * cell DFCNQ mapped to TSMC library cell DFCNQD1.
 *
 * Needs TSMC standard cell Verilog models; change D1 to use other drive strength.
 * Define DARK_CIRCUIT_FAKE_TSMC to use the fake DFCNQD1 below instead.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module DFCNQ (
    input  wire D,
    input  wire CP,  // clock
    input  wire CDN, // clear, active low
    output wire Q
);

    DFCNQD1 u_dfcnq(.D(D), .CP(CP), .CDN(CDN), .Q(Q));

endmodule

`ifdef DARK_CIRCUIT_FAKE_TSMC
module DFCNQD1 (
    input  wire D,
    input  wire CP,
    input  wire CDN,
    output reg  Q
);

    always_ff @(posedge CP or negedge CDN)
        if (!CDN)
            Q <= 1'b0;
        else
            Q <= D;

endmodule
`endif

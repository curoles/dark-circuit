/* Rising edge D Flip Flop, TSMC-style cell DFQ.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module DFQ (
    input  wire D,
    input  wire CP, // clock
    output reg  Q
);

    always_ff @(posedge CP)
        Q <= D;

endmodule

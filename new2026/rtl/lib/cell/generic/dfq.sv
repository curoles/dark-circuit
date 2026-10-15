/* Rising edge D Flip Flop, TSMC-style cell DFQ.
 *
 */
module DFQ (
    input  wire D,
    input  wire CP, // clock
    output reg  Q
);

    always_ff @(posedge CP)
        Q <= D;

endmodule

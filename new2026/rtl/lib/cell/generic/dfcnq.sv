/* Rising edge D Flip Flop with asynchronous clear, TSMC-style cell DFCNQ.
 *
 */
module DFCNQ (
    input  wire D,
    input  wire CP,  // clock
    input  wire CDN, // clear, active low
    output reg  Q
);

    always_ff @(posedge CP or negedge CDN)
        if (!CDN)
            Q <= 1'b0;
        else
            Q <= D;

endmodule

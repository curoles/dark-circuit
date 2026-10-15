/* Latch, transparent while E is 1, TSMC-style cell LHQ.
 *
 */
module LHQ (
    input  wire D,
    input  wire E, // enable
    output reg  Q
);

    always_latch
        if (E)
            Q <= D;

endmodule

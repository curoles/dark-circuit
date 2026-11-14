/* Detection events: which stabilizer outcomes changed since the last round; made of gates.
 *
 * Same ports and events as the behave version. A DffSyncRstEn keeps the round before (taken
 * with in_valid); the round before counts unless this is the first round, and an outcome is
 * an event unless the first round does not know it or there is no round:
 *
 *   last   = the round before                   (DffSyncRstEn, en = in_valid)
 *   base   = last & ~first                      (the first round compares with 0)
 *   counts = in_valid & (first_known | ~first)  (an unknown first outcome is no event)
 *   events = (syndrome ^ base) & counts
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
`include "dark_circuit_assert.svh"

module DetectionEvents #(
    parameter N = 12                    // stabilizers of the round
)(
    input  wire         clk,
    input  wire         rst_n,          // synchronous reset, active low
    input  wire         in_valid,       // syndrome is a round
    input  wire         first,          // the first round: no round before it
    input  wire [N-1:0] first_known,    // first round: outcome k is 0 unless an error
    input  wire [N-1:0] syndrome,       // the round's outcomes
    output wire [N-1:0] events          // outcome k changed; 0 while in_valid is 0
);
    `DC_STATIC_ASSERT(a_n, N >= 1)

    wire         first_n;               // ~first
    wire [N-1:0] last;                  // the round before
    wire [N-1:0] base;                  // what the round is compared with
    wire [N-1:0] changed;               // syndrome ^ base
    wire [N-1:0] known;                 // first_known | ~first
    wire [N-1:0] counts;                // the outcome can be an event

    DffSyncRstEn #(N) u_dff_sync_rst_en(.clk, .rst_n, .en(in_valid), .in(syndrome),
                                        .out(last));

    // @kb: rtl/lib/qec/detection_events/design
    Inv  #(1) u_inv(.in(first), .out(first_n));
    And2 #(N) u_and2_base(.in1(last), .in2({N{first_n}}), .out(base));
    Xor2 #(N) u_xor2(.in1(syndrome), .in2(base), .out(changed));
    Or2  #(N) u_or2(.in1(first_known), .in2({N{first_n}}), .out(known));
    And2 #(N) u_and2_counts(.in1(known), .in2({N{in_valid}}), .out(counts));
    And2 #(N) u_and2_events(.in1(changed), .in2(counts), .out(events));

endmodule

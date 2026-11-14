/* Detection events, behavioral: which stabilizer outcomes changed since the last round.
 *
 * A round of N stabilizer outcomes (one type, QecPkg) comes with in_valid; events[k] is 1
 * when outcome k differs from its value in the round before: a detection event. A data error
 * flips the outcomes of its stabilizers in every round after it, so it gives events once,
 * in the round it happened; a wrong measurement flips one outcome of one round, so it gives
 * events in two rounds at the same stabilizer. The first round (first = 1) has no round
 * before: an outcome the starting state fixes to 0 (first_known[k] = 1, such as the Z-type
 * stabilizers of a memory experiment started in |0...0>) is compared with 0, the others
 * (random in the first round) give no event. The round that a final measurement of the data
 * qubits makes (the parities computed from it) is a round like the others.
 *
 * For example, N = 4 (bit 0 first), first_known 1111:
 *   round 0 (first)  syndrome 0000   events 0000
 *   round 1          syndrome 0110   events 0110   a data error between rounds 0 and 1
 *   round 2          syndrome 0111   events 0001   a wrong measurement of stabilizer 3 ...
 *   round 3          syndrome 0110   events 0001   ... gives events in rounds 2 and 3
 *
 * events is combinational from syndrome, and 0 while in_valid is 0; the round is kept at the
 * rising edge of clk with in_valid. Reset (synchronous, active low) clears the round kept.
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

    logic [N-1:0] last;                 // the round before

    always_ff @(posedge clk)
        if (!rst_n)
            last <= '0;
        else if (in_valid)
            last <= syndrome;

    // @kb: rtl/lib/qec/detection_events/design
    assign events = !in_valid ? '0 :
                    first     ? syndrome & first_known :
                                syndrome ^ last;

endmodule

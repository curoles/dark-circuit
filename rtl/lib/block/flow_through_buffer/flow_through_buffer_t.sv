/* Flow-through buffer of type T: FlowThroughBuffer with DATA_WIDTH = $bits(T); items are
 * values of T. Same behavior as FlowThroughBuffer, behave or struct version, whichever the
 * flist has.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "dark_circuit_assert.svh"

module FlowThroughBufferT #(
    parameter type T = logic [7:0]            // type of an item
)(
    input  wire clk,
    input  wire rst_n,                        // synchronous reset, active low: empty

    input  wire in_valid,                     // channel in
    output wire in_ready,                     // the entry is empty: a flip-flop
    input  T    in_data,

    output wire out_valid,                    // channel out
    input  wire out_ready,
    output T    out_data
);
    FlowThroughBuffer #(.DATA_WIDTH($bits(T))) u_flow_through_buffer(
        .clk, .rst_n, .in_valid, .in_ready, .in_data, .out_valid, .out_ready, .out_data);

    // Valid/ready rule 2 on channel out: an offered item stays until it is taken (the entry
    // keeps the one that flowed through).
    `DC_ASSERT_NEXT(a_out_held, out_valid && !out_ready, out_valid && $stable(out_data))

    // The entry empties when out takes the held item: the next item is taken a clock later.
    `DC_ASSERT_NEXT(a_empty_after_take, !in_ready && out_ready, in_ready)

    // No rule 2 on channel in: an offer is taken at once (empty) or not at all (full), so a
    // sender may withdraw an offer that was not taken (Mig2's fetch does, kb
    // rtl/design/mig2/fetch_waits).

endmodule

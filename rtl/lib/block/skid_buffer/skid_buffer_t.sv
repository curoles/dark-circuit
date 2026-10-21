`include "dark_circuit_assert.svh"

/* Skid buffer of type T: SkidBuffer with DATA_WIDTH = $bits(T); items are values of T.
 * Same behavior as SkidBuffer, behave or struct version, whichever the flist has.
 */
module SkidBufferT #(
    parameter type T = logic [7:0]            // type of an item
)(
    input  wire clk,
    input  wire rst_n,                        // synchronous reset, active low: empty

    input  wire in_valid,                     // channel in
    output wire in_ready,
    input  T    in_data,

    output wire out_valid,                    // channel out
    input  wire out_ready,
    output T    out_data
);
    SkidBuffer #(.DATA_WIDTH($bits(T))) u_skid_buffer(
        .clk, .rst_n, .in_valid, .in_ready, .in_data, .out_valid, .out_ready, .out_data);

    // Valid/ready rule 2 on channel in: an offered item stays until it is taken.
    `DC_ASSERT_NEXT(a_in_held, in_valid && !in_ready, in_valid && $stable(in_data))

endmodule

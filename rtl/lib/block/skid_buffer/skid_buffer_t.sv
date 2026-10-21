`ifdef DARK_CIRCUIT_ENABLE_MODULE_TYPE_PARAM
/* Skid buffer of type T: SkidBuffer with DATA_WIDTH = $bits(T); items are values of T.
 * Same behavior as SkidBuffer, behave or struct version, whichever the flist has.
 * Needs a tool that supports type parameters, see DARK_CIRCUIT_ENABLE_MODULE_TYPE_PARAM
 * in AGENTS.md.
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

endmodule
`endif

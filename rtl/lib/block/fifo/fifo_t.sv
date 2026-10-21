`include "dark_circuit_assert.svh"

/* FIFO of type T: Fifo with DATA_WIDTH = $bits(T); entries are values of T (a struct,
 * an enum, a vector typedef). Same behavior and status outputs as Fifo, behave or
 * struct version, whichever the flist has.
 */
module FifoT #(
    parameter type             T            = logic [7:0],  // type of an entry
    parameter                  ADDR_WIDTH   = 3,            // 1 << ADDR_WIDTH entries
    // Thresholds have the width of count: Fifo compares count with them.
    parameter [ADDR_WIDTH:0]   ALMOST_FULL  = (1 << ADDR_WIDTH) - 1,
    parameter [ADDR_WIDTH:0]   ALMOST_EMPTY = 1
)(
    input  wire                clk,
    input  wire                rst_n,         // synchronous reset, active low
    input  wire                write,         // ignored when full
    input  T                   data_in,
    input  wire                read,          // ignored when empty
    output T                   data_out,      // oldest entry, valid when empty is 0
    output wire                empty,
    output wire                full,
    output wire [ADDR_WIDTH:0] count,         // 0..DEPTH entries
    output wire                almost_full,
    output wire                almost_empty
);
    Fifo #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH($bits(T)), .ALMOST_FULL(ALMOST_FULL),
           .ALMOST_EMPTY(ALMOST_EMPTY)) u_fifo(
        .clk, .rst_n, .write, .data_in, .read, .data_out, .empty, .full, .count,
        .almost_full, .almost_empty);

    localparam [ADDR_WIDTH:0] DEPTH = 1 << ADDR_WIDTH;

    // Status outputs agree with count, whichever Fifo version the flist has.
    `DC_ASSERT(a_empty_is_count_0, empty == (count == '0))
    `DC_ASSERT(a_full_is_count_depth, full == (count == DEPTH))

endmodule

/* FIFO of type TT with valid/ready channels: FifoT, items go in through channel in and
 * come out through channel out, oldest first. The type parameter is TT, not T:
 * Icarus 13 does not parse .T(...) of the FifoT instance inside a module whose own
 * type parameter is T.
 *
 * Channels follow the valid/ready rules (AGENTS.md): an item moves on a rising edge
 * where valid and ready are both 1; valid and data stay until then; valid does not
 * depend on ready. in_ready = not full, out_valid = not empty: both come from the FIFO
 * pointers only, never from the other side's valid or ready, so the FIFO also cuts
 * combinational paths between its two sides. An item written into an empty FIFO comes
 * out the next cycle (no pass-through). When full, a write waits even if an item leaves
 * in the same cycle (Fifo ignores write when full).
 */
module FifoVldRdyT #(
    parameter type             TT           = logic [7:0],  // type of an item
    parameter                  ADDR_WIDTH   = 3,            // 1 << ADDR_WIDTH items
    parameter [ADDR_WIDTH:0]   ALMOST_FULL  = (1 << ADDR_WIDTH) - 1,
    parameter [ADDR_WIDTH:0]   ALMOST_EMPTY = 1
)(
    input  wire                clk,
    input  wire                rst_n,         // synchronous reset, active low: empty

    input  wire                in_valid,      // channel in
    output wire                in_ready,
    input  TT                  in_data,

    output wire                out_valid,     // channel out
    input  wire                out_ready,
    output TT                  out_data,

    output wire [ADDR_WIDTH:0] count,         // 0..DEPTH items
    output wire                almost_full,
    output wire                almost_empty
);
    wire empty;
    wire full;

    // Fifo ignores write when full and read when empty: valid and ready map directly.
    FifoT #(.T(TT), .ADDR_WIDTH(ADDR_WIDTH), .ALMOST_FULL(ALMOST_FULL),
            .ALMOST_EMPTY(ALMOST_EMPTY)) u_fifo_t(
        .clk, .rst_n, .write(in_valid), .data_in(in_data), .read(out_ready),
        .data_out(out_data), .empty, .full, .count, .almost_full, .almost_empty);

    assign in_ready  = !full;
    assign out_valid = !empty;

    // Valid/ready rule 2 on channel in: an offered item stays until it is taken.
    `DC_ASSERT_NEXT(a_in_held, in_valid && !in_ready, in_valid && $stable(in_data))

endmodule

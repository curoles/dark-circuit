`ifdef DARK_CIRCUIT_ENABLE_MODULE_TYPE_PARAM
/* FIFO of type T: Fifo with DATA_WIDTH = $bits(T); entries are values of T (a struct,
 * an enum, a vector typedef). Same behavior and status outputs as Fifo, behave or
 * struct version, whichever the flist has. Needs a tool that supports type parameters,
 * see DARK_CIRCUIT_ENABLE_MODULE_TYPE_PARAM in AGENTS.md.
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

endmodule
`endif

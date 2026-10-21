/* FIFO for small depths, behavioral.
 *
 * Entries are flops, so use it for small depths; deep FIFOs need SRAM.
 * First-word fall-through: data_out is the oldest entry while empty is 0,
 * read=1 removes it on rising edge. write=1 adds data_in on rising edge.
 * Write is ignored when full and read is ignored when empty, also when the other
 * happens in the same cycle, so all status outputs depend only on the pointers.
 * Read and write in the same cycle both happen when not full and not empty.
 * almost_full is count >= ALMOST_FULL, almost_empty is count <= ALMOST_EMPTY;
 * defaults mean one entry from full and one entry from empty.
 * rst_n=0 on rising edge empties the FIFO, entries are not cleared.
 *
 * @author    Igor Lesik
 * @copyright 2020 Igor Lesik, MIT License
 */
module Fifo #(
    parameter  ADDR_WIDTH   = 3,                     // 1 << ADDR_WIDTH entries
    parameter  DATA_WIDTH   = 8,
    parameter  ALMOST_FULL  = (1 << ADDR_WIDTH) - 1,
    parameter  ALMOST_EMPTY = 1,
    localparam DEPTH        = 1 << ADDR_WIDTH
)(
    input  wire                  clk,
    input  wire                  rst_n,         // synchronous reset, active low
    input  wire                  write,         // ignored when full
    input  wire [DATA_WIDTH-1:0] data_in,
    input  wire                  read,          // ignored when empty
    output wire [DATA_WIDTH-1:0] data_out,      // oldest entry, valid when empty is 0
    output wire                  empty,
    output wire                  full,
    output wire [ADDR_WIDTH:0]   count,         // 0..DEPTH entries
    output wire                  almost_full,
    output wire                  almost_empty
);
    reg  [DATA_WIDTH-1:0] mem [DEPTH];
    reg  [ADDR_WIDTH:0]   wr_ptr;  // top bit is wrap bit
    reg  [ADDR_WIDTH:0]   rd_ptr;
    wire                  do_write;
    wire                  do_read;

    assign do_write = write & ~full;
    assign do_read  = read & ~empty;

    always_ff @(posedge clk)
        if (!rst_n) begin
            wr_ptr <= 0;
            rd_ptr <= 0;
        end else begin
            if (do_write) wr_ptr <= wr_ptr + 1'b1;
            if (do_read)  rd_ptr <= rd_ptr + 1'b1;
        end

    always_ff @(posedge clk)
        if (do_write)
            mem[wr_ptr[ADDR_WIDTH-1:0]] <= data_in;

    assign data_out     = mem[rd_ptr[ADDR_WIDTH-1:0]];
    assign count        = wr_ptr - rd_ptr;
    assign empty        = count == 0;
    assign full         = count == DEPTH;
    assign almost_full  = count >= ALMOST_FULL;
    assign almost_empty = count <= ALMOST_EMPTY;

endmodule

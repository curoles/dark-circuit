/**
 * @file
 * @brief  FIFO
 * @author Igor Lesik 2020
 */

/** FIFO
 *
 */
module Fifo #(
    parameter WIDTH = 8,
    parameter DEPTH = 8
)(
    input wire clk,
    input wire reset,
    input wire read,
    input wire write,
    input wire [WIDTH-1:0] data_in,
    input wire [WIDTH-1:0] data_out,
    output wire empty,
    output wire full
);

reg [WIDTH-1:0] fifo[DEPTH-1:0];

localparam PTR_SIZE = `CLOG(DEPTH);
reg [PTR_SIZE-1:0] wr_ptr;
reg [PTR_SIZE-1:0] rd_ptr;

assign empty = (wr_ptr == rd_ptr);
assign data_out = fifo[rd_ptr];

wire rd_ready;
assign rd_ready = ~empty;

wire [PTR_SIZE-1:0] next_wr_ptr;
wire [PTR_SIZE-1:0] next_rd_ptr;
assign next_rd_ptr = rd_ptr + PTR_SIZE'd1;
assign next_wr_ptr = wr_ptr + PTR_SIZE'd1;

always_ff @(posedge clk)
begin
    if (reset) begin
        wr_ptr <= 0;
        rd_ptr <= 0;
        full <= 0;
    end else begin
        if (read && rd_ready)
        begin: move_rd_ptr
            rd_ptr <= next_rd_ptr;
            full <= 0;
        end: move_rd_ptr

        if (write)
        begin
            if (next_wr_ptr == read_pointer) begin
                full <= 1;
            end else begin
                fifo[wr_ptr] <= data_in;
                wr_ptr <= next_wr_ptr;
            end
        end
    end
end

endmodule

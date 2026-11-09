/* DMA channel: the state of one transfer, its commands to the DMA mover; behavioral.
 *
 * start (a clock) begins a transfer of start_len bytes from start_src to start_dst while the
 * channel is idle (ignored while busy); a transfer of 0 bytes is done at once (done the next
 * clock, never busy). Every start while idle loads the state, also one of 0 bytes (the
 * PDMA copies its Next registers into Exec at every run). While busy the channel offers a
 * command with its current source, destination and bytes left (cmd_valid; held until taken,
 * the library's valid/ready rules), then waits for its done from the mover (mv_done with
 * mv_n, the bytes moved): the source and the destination advance by mv_n, the bytes left go
 * down by mv_n. When none are left,
 * done is 1 for a clock and the channel is idle. stop (a clock, or longer) ends the transfer
 * after the transaction the channel offers or has in flight: the channel never withdraws an
 * offer; it is idle with bytes left, no done. cur_src, cur_dst and left are the transfer's
 * state (the PDMA's Exec registers): after a transfer the addresses past its last byte.
 *
 *   start --> busy: offer cmd --taken--> wait --mv_done: advance by mv_n--> none left: done
 *                     ^------------ bytes left, no stop -------------+
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "dark_circuit_assert.svh"

module DmaChannel #(
    parameter ADDR_WIDTH = 32,                      // byte address
    parameter LEN_WIDTH  = 32,                      // bits of a byte count
    parameter N_WIDTH    = 4                        // bits of mv_n (the mover's done_n)
)(
    input  wire                  clk,
    input  wire                  rst_n,             // synchronous reset, active low

    // Control
    input  wire                  start,             // begin a transfer (while idle)
    input  wire [ADDR_WIDTH-1:0] start_src,
    input  wire [ADDR_WIDTH-1:0] start_dst,
    input  wire [LEN_WIDTH-1:0]  start_len,         // bytes
    input  wire                  stop,              // end it after the transaction offered
    output logic                 busy,              // a transfer is on
    output logic                 done,              // one clock: the transfer is complete
    output logic [ADDR_WIDTH-1:0] cur_src,          // its current source
    output logic [ADDR_WIDTH-1:0] cur_dst,          // ... destination
    output logic [LEN_WIDTH-1:0] left,              // ... bytes left

    // Mover
    output wire                  cmd_valid,         // a transaction from cur_src, cur_dst, left
    input  wire                  cmd_ready,
    input  wire                  mv_done,           // its done (this channel's)
    input  wire [N_WIDTH-1:0]    mv_n               // the bytes it moved
);
    `DC_STATIC_ASSERT(a_widths, LEN_WIDTH >= N_WIDTH && ADDR_WIDTH >= N_WIDTH)

    logic waiting;      // a command is taken, its done not here yet
    logic stopping;     // stop came: no command after the one offered or in flight
    logic take;
    logic last;         // the done moves the last bytes

    // @kb: rtl/lib/block/dma/design
    assign cmd_valid = busy && !waiting;
    assign take      = cmd_valid && cmd_ready;
    assign last      = left == LEN_WIDTH'(mv_n);

    always_ff @(posedge clk)
        if (!rst_n) begin
            busy     <= 1'b0;
            waiting  <= 1'b0;
            stopping <= 1'b0;
            done     <= 1'b0;
        end else begin
            done <= 1'b0;
            if (!busy) begin
                stopping <= 1'b0;
                if (start && start_len == '0)
                    done <= 1'b1;
                else if (start)
                    busy <= 1'b1;
            end else begin
                if (stop)
                    stopping <= 1'b1;
                if (take)
                    waiting <= 1'b1;
                if (mv_done) begin
                    waiting <= 1'b0;
                    if (last) begin
                        busy <= 1'b0;
                        done <= 1'b1;
                    end else if (stopping || stop)
                        busy <= 1'b0;
                end
            end
        end

    // The transfer's state: loaded at a start, advanced at each done.
    always_ff @(posedge clk)
        if (!busy && start) begin
            cur_src <= start_src;
            cur_dst <= start_dst;
            left    <= start_len;
        end else if (busy && mv_done) begin
            cur_src <= cur_src + ADDR_WIDTH'(mv_n);
            cur_dst <= cur_dst + ADDR_WIDTH'(mv_n);
            left    <= left - LEN_WIDTH'(mv_n);
        end

    // A done only for a command taken; it moves no more than is left.
    `DC_ASSERT(a_done_waited, !mv_done || (busy && waiting))
    `DC_ASSERT(a_done_le_left, !mv_done || LEN_WIDTH'(mv_n) <= left)

endmodule

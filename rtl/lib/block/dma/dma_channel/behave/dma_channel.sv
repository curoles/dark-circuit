/* DMA channel: the state of one transfer, its commands to the DMA mover; behavioral.
 *
 * A DMA channel is a job slot (one transfer at a time, its own registers in a front end);
 * not the mover's read and write channels, which are request paths (AGENTS.md
 * Terminology). start (a clock) begins a transfer of start_len bytes from start_src to
 * start_dst while the channel is idle (ignored while busy); a transfer of 0 bytes is done at
 * once (done the next clock, never busy). Every start while idle loads the state, also one of
 * 0 bytes (the PDMA copies its Next registers into Exec at every run).
 *
 * Two sets of counters (kb rtl/lib/block/dma/issue_pointer): the issue pointer (iss_src,
 * iss_dst, iss_left), where the next transaction to send starts, and the completion
 * counters (cur_src, cur_dst, left: the PDMA's Exec registers), how far the transfer has
 * landed. While busy and bytes are left to send, the channel offers a command from its issue
 * pointer (cmd_valid; held until taken, the library's valid/ready rules); when the mover
 * takes it, the issue pointer advances by the transaction's n, computed here as the mover
 * does (as many bytes as both the source's and the destination's beat still hold, at most
 * the bytes left: n = min(left, BEAT - max(src % BEAT, dst % BEAT)), BEAT = 1 << (N_WIDTH -
 * 1) bytes; the one place n is computed: it goes to the mover with the command, cmd_n, kb
 * rtl/lib/block/dma/byte_count), and the next command is offered in the clock after,
 * without waiting: the mover
 * keeps as many in flight as its depth. Each done from the mover (mv_done with mv_n, in the
 * order of the commands) advances the completion counters by mv_n. When they reach 0, done
 * is 1 for a clock and the channel is idle. So the bytes in flight are left - iss_left.
 *
 * stop (a clock, or longer) ends the transfer early: the channel sends no new command, but
 * an offer already made in an earlier clock stays until taken (the library's channels never
 * withdraw an offer), and the transactions in flight finish; when none is in flight and none
 * offered, the channel is idle with bytes left, no done, and the completion counters say
 * exactly how far it got (unless the transactions in flight finished the transfer: then it
 * is done).
 *
 *   start --> busy: offer cmd (issue pointer) --taken: issue += n--> offer the next ...
 *             mv_done: completion += mv_n --> none left: done;  stop: drain, then idle
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "dark_circuit_assert.svh"

module DmaChannel #(
    parameter  ADDR_WIDTH = 32,                     // byte address
    parameter  LEN_WIDTH  = 32,                     // bits of a byte count
    parameter  N_WIDTH    = 4,                      // bits of mv_n (the mover's done_n)
    localparam OFF_WIDTH  = N_WIDTH - 1             // bits of a byte's offset in a beat
)(
    input  wire                  clk,
    input  wire                  rst_n,             // synchronous reset, active low

    // Control
    input  wire                  start,             // begin a transfer (while idle)
    input  wire [ADDR_WIDTH-1:0] start_src,
    input  wire [ADDR_WIDTH-1:0] start_dst,
    input  wire [LEN_WIDTH-1:0]  start_len,         // bytes
    input  wire                  stop,              // end it: no new command, drain
    output logic                 busy,              // a transfer is on
    output logic                 done,              // one clock: the transfer is complete
    output logic [ADDR_WIDTH-1:0] cur_src,          // completion: its current source
    output logic [ADDR_WIDTH-1:0] cur_dst,          // ... destination
    output logic [LEN_WIDTH-1:0] left,              // ... bytes left

    // Mover
    output wire                  cmd_valid,         // a transaction from the issue pointer
    input  wire                  cmd_ready,
    output wire [ADDR_WIDTH-1:0] cmd_src,           // the issue pointer: the next source,
    output wire [ADDR_WIDTH-1:0] cmd_dst,           //   destination,
    output wire [N_WIDTH-1:0]    cmd_n,             //   the transaction's bytes (the mover's)
    input  wire                  mv_done,           // a done of this channel's, in order
    input  wire [N_WIDTH-1:0]    mv_n               // the bytes it moved
);
    `DC_STATIC_ASSERT(a_widths, LEN_WIDTH >= N_WIDTH && ADDR_WIDTH >= N_WIDTH && N_WIDTH >= 2)

    logic [ADDR_WIDTH-1:0] iss_src;     // the issue pointer
    logic [ADDR_WIDTH-1:0] iss_dst;
    logic [LEN_WIDTH-1:0]  iss_left;
    logic                  stopping;    // stop came: no new command, drain
    logic                  offered;     // an offer of an earlier clock not taken yet
    logic                  take;
    logic [N_WIDTH-1:0]    n;           // the offered transaction's bytes
    logic                  last;        // the done moves the last bytes
    logic [LEN_WIDTH-1:0]  left_next;   // the counters after this clock
    logic [LEN_WIDTH-1:0]  iss_left_next;
    logic                  offered_next;

    // The bytes a transaction moves, from the offsets of the source and the destination (the
    // mover's formula, DmaMover's bytes_of).
    function automatic logic [N_WIDTH-1:0] bytes_of(input logic [OFF_WIDTH-1:0] so,
                                                    input logic [OFF_WIDTH-1:0] d_o,
                                                    input logic [LEN_WIDTH-1:0] rest);
        logic [N_WIDTH-1:0] room;
        room = N_WIDTH'(1 << OFF_WIDTH) - N_WIDTH'((so > d_o) ? so : d_o);
        return (rest < LEN_WIDTH'(room)) ? rest[N_WIDTH-1:0] : room;
    endfunction

    // @kb: rtl/lib/block/dma/design
    // @kb: rtl/lib/block/dma/issue_pointer
    assign cmd_valid = busy && iss_left != '0 && (!stopping || offered);
    assign take      = cmd_valid && cmd_ready;
    assign cmd_src   = iss_src;
    assign cmd_dst   = iss_dst;
    assign cmd_n     = n;
    // @kb: rtl/lib/block/dma/byte_count
    assign n         = bytes_of(iss_src[OFF_WIDTH-1:0], iss_dst[OFF_WIDTH-1:0], iss_left);
    assign last      = left == LEN_WIDTH'(mv_n);

    assign left_next     = mv_done ? left - LEN_WIDTH'(mv_n) : left;
    assign iss_left_next = take ? iss_left - LEN_WIDTH'(n) : iss_left;
    assign offered_next  = cmd_valid && !take;

    always_ff @(posedge clk)
        if (!rst_n) begin
            busy     <= 1'b0;
            stopping <= 1'b0;
            offered  <= 1'b0;
            done     <= 1'b0;
        end else begin
            done    <= 1'b0;
            offered <= offered_next;
            if (!busy) begin
                stopping <= 1'b0;
                if (start && start_len == '0)
                    done <= 1'b1;
                else if (start)
                    busy <= 1'b1;
            end else begin
                if (stop)
                    stopping <= 1'b1;
                if (mv_done && last) begin
                    busy <= 1'b0;
                    done <= 1'b1;
                end else if ((stopping || stop) && left_next == iss_left_next && !offered_next)
                    busy <= 1'b0;           // stopped: nothing in flight, nothing offered
            end
        end

    // The issue pointer: loaded at a start, advanced at each take.
    always_ff @(posedge clk)
        if (!busy && start) begin
            iss_src  <= start_src;
            iss_dst  <= start_dst;
            iss_left <= start_len;
        end else if (take) begin
            iss_src  <= iss_src + ADDR_WIDTH'(n);
            iss_dst  <= iss_dst + ADDR_WIDTH'(n);
            iss_left <= iss_left_next;
        end

    // The completion counters: loaded at a start, advanced at each done.
    always_ff @(posedge clk)
        if (!busy && start) begin
            cur_src <= start_src;
            cur_dst <= start_dst;
            left    <= start_len;
        end else if (busy && mv_done) begin
            cur_src <= cur_src + ADDR_WIDTH'(mv_n);
            cur_dst <= cur_dst + ADDR_WIDTH'(mv_n);
            left    <= left_next;
        end

    // A done only for a transaction in flight, and no more bytes than are in flight.
    `DC_ASSERT(a_done_in_flight, !mv_done || (busy && left != iss_left))
    `DC_ASSERT(a_done_le_left, !mv_done || LEN_WIDTH'(mv_n) <= left - iss_left)

endmodule

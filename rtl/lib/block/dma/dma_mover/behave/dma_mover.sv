/* DMA mover: moves the bytes of one transaction of a DMA transfer, a read of the source beat
 * and a write of the destination beat on the library's memory channel; behavioral.
 *
 * A command (cmd_valid, cmd_ready; the library's valid/ready rules) gives the transfer's
 * current source and destination byte addresses and its bytes left (1 or more), and an ID
 * that the done comes back with (the channel). The mover moves n bytes, as many as both the
 * source's beat and the destination's beat still hold from those addresses, at most the
 * bytes left:
 *
 *   n = min(left, BEAT - max(src % BEAT, dst % BEAT))     (BEAT = DATA_WIDTH / 8 bytes)
 *
 * so any alignment of source and destination works, a transfer of aligned addresses moving
 * a whole beat a transaction. It reads the source's beat (its aligned address, the beat's
 * size), rotates the answer so that byte src % BEAT lands on byte dst % BEAT, and writes the
 * destination's beat with the strobes of the n bytes. Then done_valid is 1 for a clock with
 * done_id and done_n (the requester advances its addresses by n and takes n off its bytes
 * left; done has no ready: it is always taken). One transaction at a time: cmd_ready is 1
 * only while idle, from a flop. The memory side is the library's channel (as AtomicUnit's):
 * a request held until taken, the answer to a read in a later clock, in order.
 *
 *   cmd --take: n, rotation--> READ src beat --answer--> rotate --> WRITE dst beat, strobes
 *                                                                        --> done (id, n)
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "dark_circuit_assert.svh"

module DmaMover #(
    parameter  ADDR_WIDTH = 32,                     // byte address
    parameter  DATA_WIDTH = 64,                     // a beat: a power of 2, 16 bits or more
    parameter  LEN_WIDTH  = 32,                     // bits of a byte count
    parameter  ID_WIDTH   = 2,                      // bits of a command's ID
    localparam STRB_WIDTH = DATA_WIDTH / 8,         // bytes of a beat
    localparam OFF_WIDTH  = $clog2(STRB_WIDTH)      // bits of a byte's offset in a beat
)(
    input  wire                  clk,
    input  wire                  rst_n,             // synchronous reset, active low

    // Commands: one transaction of a transfer
    input  wire                  cmd_valid,
    output wire                  cmd_ready,
    input  wire [ID_WIDTH-1:0]   cmd_id,
    input  wire [ADDR_WIDTH-1:0] cmd_src,           // the transfer's current source
    input  wire [ADDR_WIDTH-1:0] cmd_dst,           // ... and destination
    input  wire [LEN_WIDTH-1:0]  cmd_left,          // its bytes left: 1 or more

    // Done: one clock, no ready
    output logic                 done_valid,
    output wire  [ID_WIDTH-1:0]  done_id,
    output wire  [OFF_WIDTH:0]   done_n,            // bytes moved: 1 to STRB_WIDTH

    // Memory side
    output wire                  mem_req_valid,
    input  wire                  mem_req_ready,
    output wire                  mem_req_we,
    output wire [ADDR_WIDTH-1:0] mem_req_addr,
    output wire [2:0]            mem_req_size,      // 1 << mem_req_size bytes: a beat
    output wire [DATA_WIDTH-1:0] mem_req_wdata,
    output wire [STRB_WIDTH-1:0] mem_req_wstrb,
    input  wire                  mem_rsp_valid,
    input  wire [DATA_WIDTH-1:0] mem_rsp_data
);
    `DC_STATIC_ASSERT(a_sizes, DATA_WIDTH >= 16 && (1 << OFF_WIDTH) == STRB_WIDTH &&
                               ADDR_WIDTH > OFF_WIDTH && LEN_WIDTH > OFF_WIDTH)

    typedef enum logic [1:0] {IDLE, READ, WAIT, WRITE} state_e;

    state_e                state;
    logic [ID_WIDTH-1:0]   id_q;
    logic [ADDR_WIDTH-1:0] src_q;           // the source's beat (aligned)
    logic [ADDR_WIDTH-1:0] dst_q;           // the destination's beat
    logic [OFF_WIDTH-1:0]  dst_off_q;       // the destination's first byte in its beat
    logic [OFF_WIDTH-1:0]  rot_q;           // bytes to rotate left: (dst - src) % BEAT
    logic [OFF_WIDTH:0]    n_q;             // bytes moved
    logic [DATA_WIDTH-1:0] data_q;          // the source's beat, rotated
    logic                  take;

    // The bytes a transaction moves, from the offsets of the source and the destination.
    function automatic logic [OFF_WIDTH:0] bytes_of(input logic [OFF_WIDTH-1:0] so,
                                                    input logic [OFF_WIDTH-1:0] d_o,
                                                    input logic [LEN_WIDTH-1:0] left);
        logic [OFF_WIDTH:0] room;
        room = (OFF_WIDTH+1)'(STRB_WIDTH) - (OFF_WIDTH+1)'((so > d_o) ? so : d_o);
        return (left < LEN_WIDTH'(room)) ? left[OFF_WIDTH:0] : room;
    endfunction

    // Rotate a beat left by k bytes.
    function automatic logic [DATA_WIDTH-1:0] rotate(input logic [DATA_WIDTH-1:0] d,
                                                     input logic [OFF_WIDTH-1:0] k);
        return (d << (8 * k)) | (d >> (DATA_WIDTH - 8 * int'(k)));
    endfunction

    // The strobes of n bytes from byte off.
    function automatic logic [STRB_WIDTH-1:0] strobes(input logic [OFF_WIDTH:0] n,
                                                      input logic [OFF_WIDTH-1:0] off);
        logic [STRB_WIDTH-1:0] s;
        for (int k = 0; k < STRB_WIDTH; k++)
            s[k] = k >= int'(off) && k < int'(off) + int'(n);
        return s;
    endfunction

    // @kb: rtl/lib/block/dma/design
    assign cmd_ready = state == IDLE;
    assign take      = cmd_valid && cmd_ready;

    always_ff @(posedge clk)
        if (!rst_n)
            state <= IDLE;
        else
            case (state)
                IDLE:    if (cmd_valid)     state <= READ;
                READ:    if (mem_req_ready) state <= WAIT;
                WAIT:    if (mem_rsp_valid) state <= WRITE;
                default: if (mem_req_ready) state <= IDLE;
            endcase

    always_ff @(posedge clk)
        if (take) begin
            id_q      <= cmd_id;
            src_q     <= {cmd_src[ADDR_WIDTH-1:OFF_WIDTH], {OFF_WIDTH{1'b0}}};
            dst_q     <= {cmd_dst[ADDR_WIDTH-1:OFF_WIDTH], {OFF_WIDTH{1'b0}}};
            dst_off_q <= cmd_dst[OFF_WIDTH-1:0];
            rot_q     <= cmd_dst[OFF_WIDTH-1:0] - cmd_src[OFF_WIDTH-1:0];
            n_q       <= bytes_of(cmd_src[OFF_WIDTH-1:0], cmd_dst[OFF_WIDTH-1:0], cmd_left);
        end

    always_ff @(posedge clk)
        if (state == WAIT && mem_rsp_valid)
            data_q <= rotate(mem_rsp_data, rot_q);

    always_ff @(posedge clk)
        if (!rst_n) done_valid <= 1'b0;
        else        done_valid <= state == WRITE && mem_req_ready;

    assign done_id = id_q;
    assign done_n  = n_q;

    assign mem_req_valid = state == READ || state == WRITE;
    assign mem_req_we    = state == WRITE;
    assign mem_req_addr  = (state == WRITE) ? dst_q : src_q;
    assign mem_req_size  = 3'(OFF_WIDTH);
    assign mem_req_wdata = data_q;
    assign mem_req_wstrb = (state == WRITE) ? strobes(n_q, dst_off_q) : '0;

    // A command has bytes left; done lasts one clock.
    `DC_ASSERT(a_left, !(cmd_valid && cmd_left == '0))
    `DC_ASSERT_NEXT(a_done_one_clock, done_valid, !done_valid)

endmodule

/* DMA mover: moves the bytes of the transactions of DMA transfers, each a read of the source
 * beat and a write of the destination beat, on a read channel and a write channel of the
 * library's kind, up to DEPTH transactions in flight; behavioral.
 *
 * A command (cmd_valid, cmd_ready; the library's valid/ready rules) gives a transaction's
 * source and destination byte addresses, its bytes n and an ID that the done comes back
 * with (the DMA channel). The requester computes n (DmaChannel, kb
 * rtl/lib/block/dma/byte_count): as many bytes as both the source's beat and the
 * destination's beat still hold from those addresses, at most the transfer's bytes left,
 *
 *   n = min(left, BEAT - max(src % BEAT, dst % BEAT))     (BEAT = DATA_WIDTH / 8 bytes)
 *
 * (a_n_fits), so any alignment of source and destination works, a transfer of aligned
 * addresses moving a whole beat a transaction. The command's read of the source's beat goes
 * out in the clock the command is taken: cmd_ready is 1 while fewer than DEPTH transactions
 * are in flight and the read channel is ready. The transaction waits in a queue (A: its
 * destination's beat, offset, rotation, n, ID); the reads' answers come in order into
 * another (D), each in the place its read reserved. Answers have no ready, so the mover
 * must always take one: the place is reserved before the read goes out, and freed only by
 * the write. Were it the other way (an answer that may wait for room, room freed by a write
 * that waits for the write channel), a full mover would hold the answer path: the network's
 * answers or a ReqDemux's owner behind it would stop, and the target the write waits for
 * might be waiting for those answers: a deadlock. The oldest answer is written as soon as
 * it is there: rotated so that byte src % BEAT lands on byte dst % BEAT, to the
 * destination's beat with the strobes of its n bytes. A transaction retires when its write
 * is taken, or, with WR_ACK, when the write's answer comes (wr_req_rsp; writes answered in
 * order, a queue R holds the transactions waiting): only then are its bytes surely at the
 * destination (kb rtl/lib/block/dma/pipelined_mover). done_valid is 1 for a clock after a
 * retire, with done_id and done_n (the requester advances its addresses by n and takes n
 * off its bytes left; done has no ready: it is always taken).
 *
 * Reads run ahead of writes by up to DEPTH transactions, so a transfer whose destination
 * starts after its source by less than DEPTH beats (DEPTH * BEAT bytes) reads bytes before
 * their write lands: such a transfer is undefined (with DEPTH 1 each read waits for the
 * write before it).
 *
 *   cmd --take: n, rotation--> READ src beat (rd_req) --> A
 *   rd_rsp --> D;  A, D heads --rotate--> WRITE dst beat, strobes (wr_req) --> retire
 *   retire (the write taken; with WR_ACK its answer, through R) --> done (id, n)
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "dark_circuit_assert.svh"

module DmaMover #(
    parameter  ADDR_WIDTH = 32,                     // byte address
    parameter  DATA_WIDTH = 64,                     // a beat: a power of 2, 16 bits or more
    parameter  ID_WIDTH   = 2,                      // bits of a command's ID
    parameter  DEPTH      = 1,                      // transactions in flight, 1 or more
    parameter  WR_ACK     = 0,                      // 1: a transaction retires at its write's
                                                    // answer, 0: when its write is taken
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
    input  wire [OFF_WIDTH:0]    cmd_n,             // its bytes: 1 to a beat's

    // Done: one clock, no ready
    output logic                 done_valid,
    output logic [ID_WIDTH-1:0]  done_id,
    output logic [OFF_WIDTH:0]   done_n,            // bytes moved: 1 to STRB_WIDTH

    // Read channel: reads of source beats, answered in order
    output wire                  rd_req_valid,
    input  wire                  rd_req_ready,
    output wire [ADDR_WIDTH-1:0] rd_req_addr,
    output wire [2:0]            rd_req_size,       // 1 << rd_req_size bytes: a beat
    input  wire                  rd_rsp_valid,
    input  wire [DATA_WIDTH-1:0] rd_rsp_data,

    // Write channel: writes of destination beats; with WR_ACK answered in order
    output wire                  wr_req_valid,
    input  wire                  wr_req_ready,
    output wire [ADDR_WIDTH-1:0] wr_req_addr,
    output wire [2:0]            wr_req_size,       // 1 << wr_req_size bytes: a beat
    output wire [DATA_WIDTH-1:0] wr_req_wdata,
    output wire [STRB_WIDTH-1:0] wr_req_wstrb,
    output wire                  wr_req_rsp,        // wants an answer: WR_ACK
    input  wire                  wr_rsp_valid       // a write's answer (WR_ACK)
);
    `DC_STATIC_ASSERT(a_sizes, DATA_WIDTH >= 16 && (1 << OFF_WIDTH) == STRB_WIDTH &&
                               ADDR_WIDTH > OFF_WIDTH &&
                               DEPTH >= 1 && (WR_ACK == 0 || WR_ACK == 1))

    localparam HW = ADDR_WIDTH - OFF_WIDTH;             // bits of a beat's address
    localparam QW = (DEPTH > 1) ? $clog2(DEPTH) : 1;    // the queues: 1 << QW >= DEPTH
    localparam CW = $clog2(DEPTH + 1);                  // bits of the count in flight
    localparam AW = HW + 2 * OFF_WIDTH + (OFF_WIDTH + 1) + ID_WIDTH;   // an entry of A
    localparam RW = OFF_WIDTH + 1 + ID_WIDTH;           // an entry of R

    // The transaction's write, as it waits in A.
    typedef struct packed {
        logic [HW-1:0]        dst;      // the destination's beat
        logic [OFF_WIDTH-1:0] dst_off;  // the destination's first byte in its beat
        logic [OFF_WIDTH-1:0] rot;      // bytes to rotate left: (dst - src) % BEAT
        logic [OFF_WIDTH:0]   n;        // bytes moved
        logic [ID_WIDTH-1:0]  id;
    } xact_t;

    logic [CW-1:0]         in_flight;   // transactions taken, not retired
    logic                  take;        // a command is taken: its read goes out
    logic [OFF_WIDTH-1:0]  max_off;     // the larger of the command's two offsets (a_n_fits)
    xact_t                 cmd_x;       // the command's transaction
    xact_t                 head;        // A's oldest: the next write
    logic [DATA_WIDTH-1:0] data;        // D's oldest: its source beat
    logic                  d_empty;
    logic                  wr_take;     // the write is taken
    logic                  retire;
    logic [RW-1:0]         retire_x;    // the retiring transaction's {n, id}
    // Status of the queues the count in flight makes unnecessary.
    /* verilator lint_off UNUSEDSIGNAL */
    logic                  a_empty, a_full, d_full, a_af, a_ae, d_af, d_ae;
    logic [QW:0]           a_count, d_count;
    /* verilator lint_on UNUSEDSIGNAL */

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
    // @kb: rtl/lib/block/dma/pipelined_mover
    // A command's read goes out in the clock it is taken, while fewer than DEPTH are in
    // flight.
    assign cmd_ready    = in_flight < CW'(DEPTH) && rd_req_ready;
    assign take         = cmd_valid && cmd_ready;
    assign rd_req_valid = cmd_valid && in_flight < CW'(DEPTH);
    assign rd_req_addr  = {cmd_src[ADDR_WIDTH-1:OFF_WIDTH], {OFF_WIDTH{1'b0}}};
    assign rd_req_size  = 3'(OFF_WIDTH);

    assign max_off       = (cmd_src[OFF_WIDTH-1:0] > cmd_dst[OFF_WIDTH-1:0])
                           ? cmd_src[OFF_WIDTH-1:0] : cmd_dst[OFF_WIDTH-1:0];
    assign cmd_x.dst     = cmd_dst[ADDR_WIDTH-1:OFF_WIDTH];
    assign cmd_x.dst_off = cmd_dst[OFF_WIDTH-1:0];
    assign cmd_x.rot     = cmd_dst[OFF_WIDTH-1:0] - cmd_src[OFF_WIDTH-1:0];
    // @kb: rtl/lib/block/dma/byte_count
    assign cmd_x.n       = cmd_n;
    assign cmd_x.id      = cmd_id;

    always_ff @(posedge clk)
        if (!rst_n)
            in_flight <= '0;
        else
            in_flight <= in_flight + CW'(take) - CW'(retire);

    // A: the transactions whose writes wait; D: their reads' answers, in order.
    Fifo #(.ADDR_WIDTH(QW), .DATA_WIDTH(AW)) u_fifo_xact(
        .clk, .rst_n, .write(take), .data_in(cmd_x), .read(wr_take), .data_out(head),
        .empty(a_empty), .full(a_full), .count(a_count), .almost_full(a_af),
        .almost_empty(a_ae));
    Fifo #(.ADDR_WIDTH(QW), .DATA_WIDTH(DATA_WIDTH)) u_fifo_data(
        .clk, .rst_n, .write(rd_rsp_valid), .data_in(rd_rsp_data), .read(wr_take),
        .data_out(data), .empty(d_empty), .full(d_full), .count(d_count),
        .almost_full(d_af), .almost_empty(d_ae));

    // The oldest answer's write: rotated into place, its bytes' strobes.
    assign wr_req_valid = !d_empty;
    assign wr_req_addr  = {head.dst, {OFF_WIDTH{1'b0}}};
    assign wr_req_size  = 3'(OFF_WIDTH);
    assign wr_req_wdata = rotate(data, head.rot);
    assign wr_req_wstrb = strobes(head.n, head.dst_off);
    assign wr_req_rsp   = WR_ACK != 0;
    assign wr_take      = wr_req_valid && wr_req_ready;

    // Retire: at the write's take, or with WR_ACK at its answer (R: the writes waiting).
    if (WR_ACK != 0) begin: g_ack
        /* verilator lint_off UNUSEDSIGNAL */
        logic          r_empty, r_full, r_af, r_ae;
        logic [QW:0]   r_count;
        /* verilator lint_on UNUSEDSIGNAL */
        Fifo #(.ADDR_WIDTH(QW), .DATA_WIDTH(RW)) u_fifo_retire(
            .clk, .rst_n, .write(wr_take), .data_in({head.n, head.id}), .read(wr_rsp_valid),
            .data_out(retire_x), .empty(r_empty), .full(r_full), .count(r_count),
            .almost_full(r_af), .almost_empty(r_ae));
        assign retire = wr_rsp_valid;
        `DC_ASSERT(a_ack_expected, !wr_rsp_valid || !r_empty)
    end else begin: g_no_ack
        assign retire   = wr_take;
        assign retire_x = {head.n, head.id};
        `DC_ASSERT(a_no_ack, !wr_rsp_valid)
    end

    always_ff @(posedge clk)
        if (!rst_n) done_valid <= 1'b0;
        else        done_valid <= retire;

    always_ff @(posedge clk)
        if (retire)
            {done_n, done_id} <= retire_x;

    // A command's bytes fit in its beats; an answer only to a read in flight.
    `DC_ASSERT(a_n_fits, !(cmd_valid && (cmd_n == '0 ||
                                         int'(cmd_n) + int'(max_off) > STRB_WIDTH)))
    `DC_ASSERT(a_answer_expected, !rd_rsp_valid || a_count > d_count)

endmodule

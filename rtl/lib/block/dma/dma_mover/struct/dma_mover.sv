/* DMA mover: moves the bytes of the transactions of DMA transfers, each a read of source beats
 * (one, or a burst of up to MAX_BURST) and a write of each destination beat, on a read
 * channel and a write channel of the library's kind, up to DEPTH transactions in flight;
 * made of blocks, parts and gates.
 *
 * Same ports and behavior as the behave version (see there). A Counter keeps the
 * transactions in flight (up at a take, down at a retire: count_en their Xor2); CmpGe with
 * DEPTH says when it is full. At the take: the burst's beats - 1 from n - 1 = n + ~0
 * (RippleCarryAdder, its bits above a beat's offset), the rotation dst - src = dst + ~src + 1
 * (RippleCarryAdder; n comes with the command); the transaction goes into Fifo A, the reads'
 * answers into Fifo D, and with WR_ACK the written beats into Fifo R. A Counter numbers the
 * beat written next (loaded with 0 at the transaction's last, CmpEq with its beats - 1); its
 * address is the transaction's first beat plus that number (RippleCarryAdder); the bytes
 * left from it on are n minus that number of beats (RippleCarryAdder on the bits above the
 * offset). The write rotates D's head by A's rotation (BarrelShifter, 8 * rotation bits);
 * its strobes are the first bytes left (a CmpGe per byte) shifted to the destination's
 * offset (BarrelShifter). Done is a DffSyncRst and a DffEn of the retiring transaction's n
 * and ID.
 *
 *   cmd --RippleCarryAdder (n - 1, dst - src)--> Fifo A {dst, off, rot, n, len, id}
 *   rd_rsp_data --> Fifo D --BarrelShifter (rotate by A's rot)--> wr_req_wdata
 *   Counter wbeat --CmpEq len--> last;  A's dst + wbeat --> wr_req_addr
 *   A's n - wbeat beats --CmpGe per byte--> first bytes --BarrelShifter (to A's dst offset)
 *       --> wr_req_wstrb
 *   retire: the last beat's write taken, or (WR_ACK) its answer through Fifo R --> done
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
    parameter  WR_ACK     = 0,                      // 1: a transaction retires at its last
                                                    // write's answer, 0: when it is taken
    parameter  MAX_BURST  = 1,                      // beats of a read burst: 1 (none), 2, 4, ...
    localparam STRB_WIDTH = DATA_WIDTH / 8,         // bytes of a beat
    localparam OFF_WIDTH  = $clog2(STRB_WIDTH),     // bits of a byte's offset in a beat
    localparam BB         = $clog2(MAX_BURST),      // bits of a beat's number in a burst
    localparam LW         = (BB > 0) ? BB : 1,      // bits of rd_req_len
    localparam NW         = OFF_WIDTH + BB + 1      // bits of a transaction's bytes
)(
    input  wire                  clk,
    input  wire                  rst_n,             // synchronous reset, active low

    // Commands: one transaction of a transfer
    input  wire                  cmd_valid,
    output wire                  cmd_ready,
    input  wire [ID_WIDTH-1:0]   cmd_id,
    input  wire [ADDR_WIDTH-1:0] cmd_src,           // the transfer's current source
    input  wire [ADDR_WIDTH-1:0] cmd_dst,           // ... and destination
    input  wire [NW-1:0]         cmd_n,             // its bytes: 1 to MAX_BURST beats'

    // Done: one clock, no ready
    output wire                  done_valid,
    output wire  [ID_WIDTH-1:0]  done_id,
    output wire  [NW-1:0]        done_n,            // bytes moved

    // Read channel: reads of source beats, answered in order, a beat an answer
    output wire                  rd_req_valid,
    input  wire                  rd_req_ready,
    output wire [ADDR_WIDTH-1:0] rd_req_addr,
    output wire [2:0]            rd_req_size,       // 1 << rd_req_size bytes: a beat
    output wire [LW-1:0]         rd_req_len,        // beats - 1 (kb rtl/lib/block/bursts)
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
                               ADDR_WIDTH > OFF_WIDTH + BB && (1 << BB) == MAX_BURST &&
                               DEPTH >= 1 && (WR_ACK == 0 || WR_ACK == 1))

    localparam HW = ADDR_WIDTH - OFF_WIDTH;             // bits of a beat's address
    localparam QW = (DEPTH > 1) ? $clog2(DEPTH) : 1;    // A: 1 << QW >= DEPTH
    // D and R: a beat each, 1 << DW >= DEPTH * MAX_BURST
    localparam DW = (DEPTH * MAX_BURST > 1) ? $clog2(DEPTH * MAX_BURST) : 1;
    localparam CW = $clog2(DEPTH + 1);                  // bits of the count in flight
    localparam AW = HW + 2 * OFF_WIDTH + NW + LW + ID_WIDTH;    // an entry of A
    localparam RW = 1 + NW + ID_WIDTH;                  // an entry of R: last, n, id

    wire [CW-1:0]         in_flight;        // transactions taken, not retired
    wire                  full;             // DEPTH of them
    wire                  room_left;        // fewer than DEPTH
    wire                  take;             // a command is taken: its read goes out
    wire                  retire;
    wire                  count_en;         // take or retire, not both
    wire [NW-1:0]         n_m1;             // cmd_n - 1
    wire [OFF_WIDTH-1:0]  src_off, dst_off; // the offsets of the command
    wire [OFF_WIDTH-1:0]  src_off_n;
    wire [OFF_WIDTH-1:0]  rot;              // (dst_off - src_off) % BEAT
    wire [HW-1:0]         h_dst;            // A's head: the transaction's first beat,
    wire [OFF_WIDTH-1:0]  h_off;            //   its first byte,
    wire [OFF_WIDTH-1:0]  h_rot;            //   its rotation,
    wire [NW-1:0]         h_n;              //   its bytes,
    wire [LW-1:0]         h_len;            //   its beats - 1,
    wire [ID_WIDTH-1:0]   h_id;             //   its ID
    wire [LW-1:0]         wbeat;            // the number of its beat written next
    wire [LW-1:0]         wbeat_n;
    wire                  wlast;            // ... its last
    wire                  a_pop;            // the last beat's write is taken
    wire [BB:0]           wrem_hi;          // the beats of n from wbeat on (bits above the
    wire [NW-1:0]         wrem;             // offset), the bytes
    wire [DATA_WIDTH-1:0] data;             // D's head: its source beat
    wire                  d_empty;
    wire                  wr_take;          // a write is taken
    wire [NW+ID_WIDTH-1:0] retire_x;        // the retiring transaction's {n, id}
    wire [STRB_WIDTH-1:0] first_n;          // byte k < wrem
    // Not needed: the adders' carries (n - 1 of n >= 1, the rotation modulo a beat, the beat's
    // address and bytes left inside the transaction), the counters' carries, the queues'
    // status the count in flight makes unnecessary.
    /* verilator lint_off UNUSEDSIGNAL */
    wire                  co_n_m1, co_rot, co_count, co_wbeat, co_waddr, co_wrem;
    wire                  a_empty, a_full, d_full, a_af, a_ae, d_af, d_ae;
    wire [QW:0]           a_count;
    wire [DW:0]           d_count;
    /* verilator lint_on UNUSEDSIGNAL */

    // @kb: rtl/lib/block/dma/design
    // @kb: rtl/lib/block/dma/pipelined_mover
    // The transactions in flight; a command's read goes out while fewer than DEPTH: a burst
    // of (n - 1) / BEAT + 1 beats.
    Xor2 #(1) u_xor2_count_en(.in1(take), .in2(retire), .out(count_en));
    Counter #(.WIDTH(CW)) u_counter_in_flight(
        .clk, .rst_n, .load(1'b0), .in('0), .up_down(take), .count_en, .out(in_flight),
        .co(co_count));
    CmpGe #(CW) u_cmp_ge_full(.in1(in_flight), .in2(CW'(DEPTH)), .ge(full));
    Inv  #(1) u_inv_full(.in(full), .out(room_left));
    And2 #(1) u_and2_cmd_ready(.in1(room_left), .in2(rd_req_ready), .out(cmd_ready));
    And2 #(1) u_and2_rd_valid(.in1(cmd_valid), .in2(room_left), .out(rd_req_valid));
    And2 #(1) u_and2_take(.in1(cmd_valid), .in2(cmd_ready), .out(take));
    // @kb: rtl/lib/block/dma/read_bursts
    RippleCarryAdder #(NW) u_ripple_carry_adder_n_m1(
        .in1(cmd_n), .in2({NW{1'b1}}), .ci(1'b0), .co(co_n_m1), .sum(n_m1));
    assign rd_req_addr = {cmd_src[ADDR_WIDTH-1:OFF_WIDTH], {OFF_WIDTH{1'b0}}};
    assign rd_req_size = 3'(OFF_WIDTH);
    assign rd_req_len  = n_m1[OFF_WIDTH +: LW];

    // The transaction: the rotation, from the command (n comes with it).
    assign src_off = cmd_src[OFF_WIDTH-1:0];
    assign dst_off = cmd_dst[OFF_WIDTH-1:0];
    Inv  #(OFF_WIDTH) u_inv_src_off(.in(src_off), .out(src_off_n));
    RippleCarryAdder #(OFF_WIDTH) u_ripple_carry_adder_rot(
        .in1(dst_off), .in2(src_off_n), .ci(1'b1), .co(co_rot), .sum(rot));

    // A: the transactions whose writes wait (one leaves at its last beat's write); D: their
    // reads' answers, a beat each, in order.
    // @kb: rtl/lib/block/dma/byte_count
    Fifo #(.ADDR_WIDTH(QW), .DATA_WIDTH(AW)) u_fifo_xact(
        .clk, .rst_n, .write(take),
        .data_in({cmd_dst[ADDR_WIDTH-1:OFF_WIDTH], dst_off, rot, cmd_n, rd_req_len, cmd_id}),
        .read(a_pop), .data_out({h_dst, h_off, h_rot, h_n, h_len, h_id}), .empty(a_empty),
        .full(a_full), .count(a_count), .almost_full(a_af), .almost_empty(a_ae));
    Fifo #(.ADDR_WIDTH(DW), .DATA_WIDTH(DATA_WIDTH)) u_fifo_data(
        .clk, .rst_n, .write(rd_rsp_valid), .data_in(rd_rsp_data), .read(wr_take),
        .data_out(data), .empty(d_empty), .full(d_full), .count(d_count),
        .almost_full(d_af), .almost_empty(d_ae));

    // The beat written next: its number, the last one, its address, the bytes left from it.
    Counter #(.WIDTH(LW)) u_counter_wbeat(
        .clk, .rst_n, .load(a_pop), .in('0), .up_down(1'b1), .count_en(wr_take), .out(wbeat),
        .co(co_wbeat));
    CmpEq #(LW) u_cmp_eq_wlast(.in1(wbeat), .in2(h_len), .eq(wlast));
    And2 #(1) u_and2_a_pop(.in1(wr_take), .in2(wlast), .out(a_pop));
    RippleCarryAdder #(HW) u_ripple_carry_adder_waddr(
        .in1(h_dst), .in2(HW'(wbeat)), .ci(1'b0), .co(co_waddr),
        .sum(wr_req_addr[ADDR_WIDTH-1:OFF_WIDTH]));
    assign wr_req_addr[OFF_WIDTH-1:0] = '0;
    Inv  #(LW) u_inv_wbeat(.in(wbeat), .out(wbeat_n));
    RippleCarryAdder #(BB+1) u_ripple_carry_adder_wrem(
        .in1(h_n[NW-1:OFF_WIDTH]), .in2((BB+1)'({1'b1, wbeat_n})), .ci(1'b1), .co(co_wrem),
        .sum(wrem_hi));
    assign wrem = {wrem_hi, h_n[OFF_WIDTH-1:0]};

    // The oldest answer's write: rotated into place, its bytes' strobes (a burst's offset is
    // 0; a single beat is beat 0).
    Inv  #(1) u_inv_wr_valid(.in(d_empty), .out(wr_req_valid));
    assign wr_req_size = 3'(OFF_WIDTH);
    BarrelShifter #(.WIDTH(DATA_WIDTH)) u_barrel_shifter_data(
        .in(data), .shift_in_bit(1'b0), .shift({h_rot, 3'b000}), .shift_rotate(1'b0),
        .left_right(1'b1), .out(wr_req_wdata));
    for (genvar k = 0; k < STRB_WIDTH; k++) begin: g_first
        CmpGe #(NW) u_cmp_ge(.in1(wrem), .in2(NW'(k + 1)), .ge(first_n[k]));
    end
    BarrelShifter #(.WIDTH(STRB_WIDTH)) u_barrel_shifter_strb(
        .in(first_n), .shift_in_bit(1'b0), .shift(h_off), .shift_rotate(1'b1),
        .left_right(1'b1), .out(wr_req_wstrb));
    assign wr_req_rsp = WR_ACK != 0;
    And2 #(1) u_and2_wr_take(.in1(wr_req_valid), .in2(wr_req_ready), .out(wr_take));

    // Retire: at the last beat's write, or with WR_ACK at its answer (R: the beats waiting).
    if (WR_ACK != 0) begin: g_ack
        wire [RW-1:0] r_head;       // the oldest write waiting for its answer
        /* verilator lint_off UNUSEDSIGNAL */
        wire          r_empty, r_full, r_af, r_ae;
        wire [DW:0]   r_count;
        /* verilator lint_on UNUSEDSIGNAL */
        Fifo #(.ADDR_WIDTH(DW), .DATA_WIDTH(RW)) u_fifo_retire(
            .clk, .rst_n, .write(wr_take), .data_in({wlast, h_n, h_id}), .read(wr_rsp_valid),
            .data_out(r_head), .empty(r_empty), .full(r_full), .count(r_count),
            .almost_full(r_af), .almost_empty(r_ae));
        And2 #(1) u_and2_retire(.in1(wr_rsp_valid), .in2(r_head[RW-1]), .out(retire));
        assign retire_x = r_head[RW-2:0];
        `DC_ASSERT(a_ack_expected, !wr_rsp_valid || !r_empty)
    end else begin: g_no_ack
        assign retire   = a_pop;
        assign retire_x = {h_n, h_id};
        `DC_ASSERT(a_no_ack, !wr_rsp_valid)
    end

    // Done: a clock after the retire.
    DffSyncRst #(.WIDTH(1)) u_dff_sync_rst_done(.clk, .rst_n, .in(retire), .out(done_valid));
    DffEn #(NW+ID_WIDTH) u_dff_en_done(.clk, .en(retire), .in(retire_x), .out({done_n, done_id}));

    // See the behave version.
    `DC_ASSERT(a_n_fits, !(cmd_valid && (cmd_n == '0 ||
        ((int'(cmd_n) + int'(src_off) > STRB_WIDTH || int'(cmd_n) + int'(dst_off) > STRB_WIDTH)
         && !(src_off == '0 && dst_off == '0 &&
              (int'(cmd_src) >> OFF_WIDTH) % MAX_BURST + (int'(n_m1) >> OFF_WIDTH) < MAX_BURST)))))
    `DC_ASSERT(a_answer_expected, !rd_rsp_valid || !a_empty)

endmodule

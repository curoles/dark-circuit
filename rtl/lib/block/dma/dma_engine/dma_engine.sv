/* DMA engine: N_CHANNELS DMA channels sharing one DMA mover on the library's memory channel,
 * wiring only; the part every DMA front end (a register map) is built on.
 *
 * Each channel c is controlled by its own start, start_src, start_dst, start_len and stop
 * and shows busy, done, cur_src, cur_dst and left (DmaChannel, see there). The channels'
 * commands meet at a RoundRobinArbiter; the winner's command (MuxOneHot) goes to the mover
 * with the channel's number as its ID (PriorityEncoder of the grant), and the mover's done
 * goes back to that channel (Decoder of done_id). An offer the mover does not take at once
 * stays the same (the library's valid/ready rules): while it waits the arbiter sees only the
 * waiting channel's request (a flop remembers the grant), so a channel that starts to
 * request meanwhile cannot change it, and the arbiter's order moves on with the right
 * winner. One transaction in flight for all channels; a channel waits at most N_CHANNELS - 1
 * transactions of the others.
 *
 *   channel 0 ..N-1 --cmd--> RoundRobinArbiter (lock while waiting) --MuxOneHot, ID-->
 *       DmaMover <--> memory;   done_id --Decoder--> that channel's mv_done
 *
 * One file for the behave and the struct library: the parts of the library it is built with
 * give the version.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "dark_circuit_assert.svh"

module DmaEngine #(
    parameter  N_CHANNELS = 4,                      // 1 or more
    parameter  ADDR_WIDTH = 32,                     // byte address
    parameter  DATA_WIDTH = 64,                     // a beat: a power of 2, 16 bits or more
    parameter  LEN_WIDTH  = 32,                     // bits of a byte count
    localparam STRB_WIDTH = DATA_WIDTH / 8,
    localparam N_WIDTH    = $clog2(STRB_WIDTH) + 1, // bits of a transaction's bytes
    localparam ID_WIDTH   = (N_CHANNELS > 1) ? $clog2(N_CHANNELS) : 1,
    localparam N          = N_CHANNELS
)(
    input  wire                         clk,
    input  wire                         rst_n,      // synchronous reset, active low

    // The channels' control (DmaChannel)
    input  wire [N-1:0]                 start,
    input  wire [N-1:0][ADDR_WIDTH-1:0] start_src,
    input  wire [N-1:0][ADDR_WIDTH-1:0] start_dst,
    input  wire [N-1:0][LEN_WIDTH-1:0]  start_len,
    input  wire [N-1:0]                 stop,
    output wire [N-1:0]                 busy,
    output wire [N-1:0]                 done,
    output wire [N-1:0][ADDR_WIDTH-1:0] cur_src,
    output wire [N-1:0][ADDR_WIDTH-1:0] cur_dst,
    output wire [N-1:0][LEN_WIDTH-1:0]  left,

    // Memory side
    output wire                         mem_req_valid,
    input  wire                         mem_req_ready,
    output wire                         mem_req_we,
    output wire [ADDR_WIDTH-1:0]        mem_req_addr,
    output wire [2:0]                   mem_req_size,
    output wire [DATA_WIDTH-1:0]        mem_req_wdata,
    output wire [STRB_WIDTH-1:0]        mem_req_wstrb,
    input  wire                         mem_rsp_valid,
    input  wire [DATA_WIDTH-1:0]        mem_rsp_data
);
    localparam CW = 2 * ADDR_WIDTH + LEN_WIDTH;     // a command's fields
    localparam IN = 1 << ID_WIDTH;                  // IDs

    `DC_STATIC_ASSERT(a_channels, N_CHANNELS >= 1)

    wire [N-1:0]          req;              // channel c offers a command
    wire [N-1:0]          arb_req;          // what the arbiter sees
    wire [N-1:0]          grant;            // one-hot: the channel whose command goes now
    wire [N-1:0]          grant_q;          // the grant of the clock before
    wire                  lock;             // an offer waits: keep its grant
    wire                  lock_next;
    wire                  mv_cmd_valid;     // the mover's command channel
    wire                  mv_cmd_ready;
    wire                  mv_cmd_ready_n;
    // The arbiter's advance: no arbiter for one channel.
    /* verilator lint_off UNUSEDSIGNAL */
    wire                  mv_take;          // the mover takes a command now
    /* verilator lint_on UNUSEDSIGNAL */
    wire [N-1:0]          chan_ready;       // ... channel c's
    wire [N-1:0][CW-1:0]  cmds;             // every channel's command
    wire [CW-1:0]         cmd;              // the winner's
    wire [ID_WIDTH-1:0]   cmd_id;
    wire                  done_valid;       // the mover's done
    wire [ID_WIDTH-1:0]   done_id;
    wire [N_WIDTH-1:0]    done_n;
    // IDs above the last channel are never used; the encoder's valid is mv_cmd_valid.
    /* verilator lint_off UNUSEDSIGNAL */
    wire [IN-1:0]         mv_done;          // channel c's done
    wire                  id_valid;
    /* verilator lint_on UNUSEDSIGNAL */

    // @kb: rtl/lib/block/dma/design
    for (genvar c = 0; c < N; c++) begin: g_channel
        assign cmds[c] = {cur_src[c], cur_dst[c], left[c]};
        DmaChannel #(.ADDR_WIDTH(ADDR_WIDTH), .LEN_WIDTH(LEN_WIDTH), .N_WIDTH(N_WIDTH))
            u_channel(
                .clk, .rst_n, .start(start[c]), .start_src(start_src[c]),
                .start_dst(start_dst[c]), .start_len(start_len[c]), .stop(stop[c]),
                .busy(busy[c]), .done(done[c]), .cur_src(cur_src[c]), .cur_dst(cur_dst[c]),
                .left(left[c]), .cmd_valid(req[c]), .cmd_ready(chan_ready[c]),
                .mv_done(mv_done[c]), .mv_n(done_n));
    end

    // The arbiter: while an offer waits it sees only the waiting channel.
    Mux2 #(N) u_mux2_arb_req(.in0(req), .in1(grant_q), .sel(lock), .out(arb_req));
    if (N > 1) begin: g_arbiter
        RoundRobinArbiter #(.N(N)) u_arbiter(
            .clk, .rst_n, .req(arb_req), .advance(mv_take), .grant);
    end else begin: g_one
        assign grant = arb_req;
    end
    DffEn #(N) u_dff_en_grant(.clk, .en(1'b1), .in(grant), .out(grant_q));
    OrReduce #(N) u_or_reduce_valid(.in(grant), .out(mv_cmd_valid));
    And2 #(1) u_and2_take(.in1(mv_cmd_valid), .in2(mv_cmd_ready), .out(mv_take));
    Inv  #(1) u_inv_ready(.in(mv_cmd_ready), .out(mv_cmd_ready_n));
    And2 #(1) u_and2_lock(.in1(mv_cmd_valid), .in2(mv_cmd_ready_n), .out(lock_next));
    DffSyncRst #(.WIDTH(1)) u_dff_sync_rst_lock(.clk, .rst_n, .in(lock_next), .out(lock));
    And2 #(N) u_and2_chan_ready(.in1(grant), .in2({N{mv_cmd_ready}}), .out(chan_ready));

    // The winner's command and its ID.
    MuxOneHot #(.N(N), .WIDTH(CW)) u_mux_one_hot_cmd(.in(cmds), .sel(grant), .out(cmd));
    PriorityEncoder #(.SIZE(ID_WIDTH)) u_priority_encoder_id(
        .in({{(IN-N){1'b0}}, grant}), .out(cmd_id), .valid(id_valid));

    DmaMover #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH), .LEN_WIDTH(LEN_WIDTH),
               .ID_WIDTH(ID_WIDTH)) u_mover(
        .clk, .rst_n, .cmd_valid(mv_cmd_valid), .cmd_ready(mv_cmd_ready), .cmd_id,
        .cmd_src(cmd[CW-1 -: ADDR_WIDTH]), .cmd_dst(cmd[LEN_WIDTH +: ADDR_WIDTH]),
        .cmd_left(cmd[LEN_WIDTH-1:0]), .done_valid, .done_id, .done_n,
        .mem_req_valid, .mem_req_ready, .mem_req_we, .mem_req_addr, .mem_req_size,
        .mem_req_wdata, .mem_req_wstrb, .mem_rsp_valid, .mem_rsp_data);

    // The done to its channel.
    Decoder #(.SIZE(ID_WIDTH)) u_decoder_done(.in(done_id), .en(done_valid), .out(mv_done));

    // One winner at most; an offer that waits stays the same.
    `DC_ASSERT(a_one_grant, $onehot0(grant))
    `DC_ASSERT_NEXT(a_offer_held, mv_cmd_valid && !mv_cmd_ready,
                    mv_cmd_valid && $stable(cmd_id) && $stable(cmd))

endmodule

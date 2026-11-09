/* DMA mover: moves the bytes of one transaction of a DMA transfer, a read of the source beat
 * and a write of the destination beat on the library's memory channel; made of blocks,
 * parts and gates.
 *
 * Same ports and behavior as the behave version (see there). The state is one-hot, four
 * flops (idle, read, wait, write). At the take: the larger of the two offsets (CmpGe, Mux2),
 * the room left in the beats, BEAT - max = ~max + 1 (Inv, Incr: its carry is the bit for a
 * whole beat), n = min(left, room) (CmpGe, Mux2), the rotation dst - src = dst + ~src + 1
 * (RippleCarryAdder); DffEns keep them with the beats' addresses and the ID. The answer is
 * rotated by a BarrelShifter (8 * rotation bits) into a DffEn; the strobes are the first n
 * bytes (a CmpGe per byte) shifted to the destination's offset by a BarrelShifter.
 *
 *   cmd --CmpGe, Mux2, Inv, Incr, RippleCarryAdder--> DffEn (n, rot, beats, id)
 *   mem_rsp_data --BarrelShifter (rotate)--> DffEn data --> mem_req_wdata
 *   n --CmpGe per byte--> first n --BarrelShifter (shift to dst offset)--> mem_req_wstrb
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
    output wire                  done_valid,
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

    localparam HW = ADDR_WIDTH - OFF_WIDTH;         // bits of a beat's address

    wire                  idle, read, wait_q, write;    // the state, one-hot
    wire                  idle_next, read_next, wait_next, write_next;
    wire                  take;             // a command is taken now
    wire                  read_done;        // the read is taken now
    wire                  got;              // its answer comes now
    wire                  write_done;       // the write is taken now
    wire                  cmd_valid_n, req_ready_n, rsp_valid_n;
    wire                  idle_stay, read_stay, wait_stay, write_stay;
    wire [OFF_WIDTH-1:0]  src_off, dst_off; // the offsets of the command
    wire                  src_ge;           // src_off >= dst_off
    wire [OFF_WIDTH-1:0]  off_max;
    wire [OFF_WIDTH-1:0]  off_max_n;
    wire [OFF_WIDTH:0]    room;             // BEAT - off_max
    wire                  left_ge;          // cmd_left >= room
    wire [OFF_WIDTH:0]    n;                // min(cmd_left, room)
    wire [OFF_WIDTH-1:0]  src_off_n;
    wire [OFF_WIDTH-1:0]  rot;              // (dst_off - src_off) % BEAT
    wire [HW-1:0]         src_q, dst_q;     // the beats
    wire [OFF_WIDTH-1:0]  dst_off_q;
    wire [OFF_WIDTH-1:0]  rot_q;
    wire [OFF_WIDTH:0]    n_q;
    wire [ID_WIDTH-1:0]   id_q;
    wire [DATA_WIDTH-1:0] rotated;
    wire [DATA_WIDTH-1:0] data_q;
    wire [STRB_WIDTH-1:0] first_n;          // byte k < n_q
    wire [STRB_WIDTH-1:0] strb;             // first_n at the destination's offset
    wire [HW-1:0]         beat;             // the beat of the request
    // Not needed: the rotation's carry (it is modulo a beat).
    /* verilator lint_off UNUSEDSIGNAL */
    wire                  co_rot;
    /* verilator lint_on UNUSEDSIGNAL */

    // @kb: rtl/lib/block/dma/design
    // The state: idle (reset), read, wait, write.
    Inv  #(1) u_inv_cmd_valid(.in(cmd_valid), .out(cmd_valid_n));
    Inv  #(1) u_inv_req_ready(.in(mem_req_ready), .out(req_ready_n));
    Inv  #(1) u_inv_rsp_valid(.in(mem_rsp_valid), .out(rsp_valid_n));
    And2 #(1) u_and2_take(.in1(idle), .in2(cmd_valid), .out(take));
    And2 #(1) u_and2_read_done(.in1(read), .in2(mem_req_ready), .out(read_done));
    And2 #(1) u_and2_got(.in1(wait_q), .in2(mem_rsp_valid), .out(got));
    And2 #(1) u_and2_write_done(.in1(write), .in2(mem_req_ready), .out(write_done));
    And2 #(1) u_and2_idle_stay(.in1(idle), .in2(cmd_valid_n), .out(idle_stay));
    And2 #(1) u_and2_read_stay(.in1(read), .in2(req_ready_n), .out(read_stay));
    And2 #(1) u_and2_wait_stay(.in1(wait_q), .in2(rsp_valid_n), .out(wait_stay));
    And2 #(1) u_and2_write_stay(.in1(write), .in2(req_ready_n), .out(write_stay));
    Or2  #(1) u_or2_idle(.in1(idle_stay), .in2(write_done), .out(idle_next));
    Or2  #(1) u_or2_read(.in1(read_stay), .in2(take), .out(read_next));
    Or2  #(1) u_or2_wait(.in1(wait_stay), .in2(read_done), .out(wait_next));
    Or2  #(1) u_or2_write(.in1(write_stay), .in2(got), .out(write_next));
    DffSyncRst #(.WIDTH(4), .RST_VAL(4'b0001)) u_dff_sync_rst_state(
        .clk, .rst_n, .in({write_next, wait_next, read_next, idle_next}),
        .out({write, wait_q, read, idle}));
    assign cmd_ready = idle;

    // The transaction: n and the rotation, from the command.
    assign src_off = cmd_src[OFF_WIDTH-1:0];
    assign dst_off = cmd_dst[OFF_WIDTH-1:0];
    CmpGe #(OFF_WIDTH) u_cmp_ge_off(.in1(src_off), .in2(dst_off), .ge(src_ge));
    Mux2 #(OFF_WIDTH) u_mux2_off_max(.in0(dst_off), .in1(src_off), .sel(src_ge), .out(off_max));
    Inv  #(OFF_WIDTH) u_inv_off_max(.in(off_max), .out(off_max_n));
    Incr #(.WIDTH(OFF_WIDTH)) u_incr_room(.in(off_max_n), .out(room[OFF_WIDTH-1:0]),
                                          .co(room[OFF_WIDTH]));
    CmpGe #(LEN_WIDTH) u_cmp_ge_left(.in1(cmd_left), .in2({{(LEN_WIDTH-OFF_WIDTH-1){1'b0}}, room}),
                                     .ge(left_ge));
    Mux2 #(OFF_WIDTH+1) u_mux2_n(.in0(cmd_left[OFF_WIDTH:0]), .in1(room), .sel(left_ge), .out(n));
    Inv  #(OFF_WIDTH) u_inv_src_off(.in(src_off), .out(src_off_n));
    RippleCarryAdder #(OFF_WIDTH) u_ripple_carry_adder_rot(
        .in1(dst_off), .in2(src_off_n), .ci(1'b1), .co(co_rot), .sum(rot));
    DffEn #(2 * HW + 3 * OFF_WIDTH + 1 + ID_WIDTH) u_dff_en_cmd(
        .clk, .en(take),
        .in({cmd_src[ADDR_WIDTH-1:OFF_WIDTH], cmd_dst[ADDR_WIDTH-1:OFF_WIDTH], dst_off, rot, n,
             cmd_id}),
        .out({src_q, dst_q, dst_off_q, rot_q, n_q, id_q}));

    // The data: the source's beat rotated, at its answer.
    BarrelShifter #(.WIDTH(DATA_WIDTH)) u_barrel_shifter_data(
        .in(mem_rsp_data), .shift_in_bit(1'b0), .shift({rot_q, 3'b000}), .shift_rotate(1'b0),
        .left_right(1'b1), .out(rotated));
    DffEn #(DATA_WIDTH) u_dff_en_data(.clk, .en(got), .in(rotated), .out(data_q));

    // The strobes: the first n bytes, at the destination's offset.
    for (genvar k = 0; k < STRB_WIDTH; k++) begin: g_first
        CmpGe #(OFF_WIDTH+1) u_cmp_ge(.in1(n_q), .in2((OFF_WIDTH+1)'(k + 1)), .ge(first_n[k]));
    end
    BarrelShifter #(.WIDTH(STRB_WIDTH)) u_barrel_shifter_strb(
        .in(first_n), .shift_in_bit(1'b0), .shift(dst_off_q), .shift_rotate(1'b1),
        .left_right(1'b1), .out(strb));

    // The memory request: the source's beat to read, the destination's to write.
    Or2  #(1) u_or2_req_valid(.in1(read), .in2(write), .out(mem_req_valid));
    assign mem_req_we = write;
    Mux2 #(HW) u_mux2_beat(.in0(src_q), .in1(dst_q), .sel(write), .out(beat));
    assign mem_req_addr  = {beat, {OFF_WIDTH{1'b0}}};
    assign mem_req_size  = 3'(OFF_WIDTH);
    assign mem_req_wdata = data_q;
    And2 #(STRB_WIDTH) u_and2_wstrb(.in1(strb), .in2({STRB_WIDTH{write}}), .out(mem_req_wstrb));

    // Done: a clock after the write is taken.
    DffSyncRst #(.WIDTH(1)) u_dff_sync_rst_done(.clk, .rst_n, .in(write_done), .out(done_valid));
    assign done_id = id_q;
    assign done_n  = n_q;

    // See the behave version.
    `DC_ASSERT(a_left, !(cmd_valid && cmd_left == '0))
    `DC_ASSERT_NEXT(a_done_one_clock, done_valid, !done_valid)

endmodule

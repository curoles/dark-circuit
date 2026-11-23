/* Request burst splitter: a burst read on a request channel goes out as its single beats to
 * a target that takes no bursts; made of blocks, parts and gates.
 *
 * Same ports and behavior as the behave version (see there). busy is a DffSyncRst: set when
 * a request with req_len above 0 (OrReduce) is taken, cleared when the burst's last beat is
 * taken. The copy (address, size, length, fields) is a DffEn, enabled at a take. A Counter
 * numbers the beats: loaded with 1 at a take, up at each beat taken while busy; CmpEq with
 * the copy's length says the last. A beat's address is the copy's plus k << size
 * (BarrelShifter, RippleCarryAdder). Mux2s pick the request (idle) or the copy's beat
 * (busy) for the target.
 *
 *   req_len --OrReduce--> burst;  take = req_valid AND (NOT busy AND tgt_req_ready)
 *   take --> DffEn {addr, size, len, fields};  Counter k (load 1, up while busy)
 *   k --BarrelShifter (<< size)--> RippleCarryAdder (+ addr) --Mux2 (busy)--> tgt_req_addr
 *   k CmpEq len: last;  busy: DffSyncRst (take AND burst) OR (busy AND NOT (tgt take AND last))
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "dark_circuit_assert.svh"

module ReqBurstSplit #(
    parameter ADDR_WIDTH   = 32,        // byte address
    parameter FIELDS_WIDTH = 32,        // bits of the other fields, copied to every beat
    parameter LEN_WIDTH    = 4          // bits of req_len: bursts of up to 1 << it beats
)(
    input  wire                    clk,
    input  wire                    rst_n,           // synchronous, active low
    // Requester
    input  wire                    req_valid,
    output wire                    req_ready,       // taken with the first beat
    input  wire                    req_we,          // a write
    input  wire                    req_rsp,         // wants an answer
    input  wire [LEN_WIDTH-1:0]    req_len,         // beats - 1: 0 unless a read
    input  wire [ADDR_WIDTH-1:0]   req_addr,        // byte address of beat 0
    input  wire [2:0]              req_size,        // 1 << req_size bytes a beat
    input  wire [FIELDS_WIDTH-1:0] req_fields,
    // Target: single beats
    output wire                    tgt_req_valid,
    input  wire                    tgt_req_ready,
    output wire                    tgt_req_we,
    output wire                    tgt_req_rsp,
    output wire [ADDR_WIDTH-1:0]   tgt_req_addr,
    output wire [2:0]              tgt_req_size,
    output wire [FIELDS_WIDTH-1:0] tgt_req_fields
);
    `DC_STATIC_ASSERT(a_sizes, ADDR_WIDTH >= 8 && FIELDS_WIDTH >= 1 && LEN_WIDTH >= 1)

    localparam SW = $clog2(ADDR_WIDTH);         // bits of a shift of the address
    localparam CW = ADDR_WIDTH + 3 + LEN_WIDTH + FIELDS_WIDTH;     // the copy

    wire                    busy;       // beats 1 .. len_q of a burst go out from the copy
    wire                    busy_n;
    wire                    burst;      // req_len above 0
    wire                    take;       // the requester's request is taken (its beat 0)
    wire                    start;      // ... a burst
    wire                    tgt_take;   // the target takes a beat
    wire                    next_beat;  // ... while busy
    wire                    last;       // the beat out is the burst's last
    wire                    finish;     // ... taken
    wire                    finish_n;
    wire                    busy_stay;
    wire                    busy_next;
    wire [LEN_WIDTH-1:0]    k;          // the number of the beat out while busy
    wire [ADDR_WIDTH-1:0]   addr_q;     // the copy
    wire [2:0]              size_q;
    wire [LEN_WIDTH-1:0]    len_q;
    wire [FIELDS_WIDTH-1:0] fields_q;
    wire [ADDR_WIDTH-1:0]   offset;     // k << size_q
    wire [ADDR_WIDTH-1:0]   beat_addr;  // addr_q + offset
    // Not needed: the carries (the address wraps; k stops at len_q).
    /* verilator lint_off UNUSEDSIGNAL */
    wire                    co_addr, co_k;
    /* verilator lint_on UNUSEDSIGNAL */

    // @kb: rtl/lib/block/req_burst_split/design
    // Idle: the request itself, beat 0, taken with the target's ready.
    Inv  #(1) u_inv_busy(.in(busy), .out(busy_n));
    And2 #(1) u_and2_req_ready(.in1(busy_n), .in2(tgt_req_ready), .out(req_ready));
    Or2  #(1) u_or2_tgt_valid(.in1(busy), .in2(req_valid), .out(tgt_req_valid));
    And2 #(1) u_and2_take(.in1(req_valid), .in2(req_ready), .out(take));
    And2 #(1) u_and2_tgt_take(.in1(tgt_req_valid), .in2(tgt_req_ready), .out(tgt_take));
    OrReduce #(LEN_WIDTH) u_or_reduce_burst(.in(req_len), .out(burst));
    And2 #(1) u_and2_start(.in1(take), .in2(burst), .out(start));

    // The copy, and the beat counter: 1 at a take, up at each beat taken while busy.
    DffEn #(CW) u_dff_en_copy(.clk, .en(take), .in({req_addr, req_size, req_len, req_fields}),
                              .out({addr_q, size_q, len_q, fields_q}));
    And2 #(1) u_and2_next_beat(.in1(busy), .in2(tgt_take), .out(next_beat));
    Counter #(.WIDTH(LEN_WIDTH)) u_counter_beat(
        .clk, .rst_n, .load(take), .in(LEN_WIDTH'(1)), .up_down(1'b1), .count_en(next_beat),
        .out(k), .co(co_k));
    CmpEq #(LEN_WIDTH) u_cmp_eq_last(.in1(k), .in2(len_q), .eq(last));

    // Busy from a burst's take until its last beat is taken.
    And2 #(1) u_and2_finish(.in1(next_beat), .in2(last), .out(finish));
    Inv  #(1) u_inv_finish(.in(finish), .out(finish_n));
    And2 #(1) u_and2_busy_stay(.in1(busy), .in2(finish_n), .out(busy_stay));
    Or2  #(1) u_or2_busy_next(.in1(start), .in2(busy_stay), .out(busy_next));
    DffSyncRst #(.WIDTH(1)) u_dff_sync_rst_busy(.clk, .rst_n, .in(busy_next), .out(busy));

    // The beat's address: the copy's plus k << size.
    BarrelShifter #(.WIDTH(ADDR_WIDTH)) u_barrel_shifter_offset(
        .in(ADDR_WIDTH'(k)), .shift_in_bit(1'b0), .shift(SW'(size_q)), .shift_rotate(1'b1),
        .left_right(1'b1), .out(offset));
    RippleCarryAdder #(ADDR_WIDTH) u_ripple_carry_adder_addr(
        .in1(addr_q), .in2(offset), .ci(1'b0), .co(co_addr), .sum(beat_addr));

    // To the target: the request (idle) or the copy's beat, a read (busy).
    Mux2 #(1) u_mux2_we(.in0(req_we), .in1(1'b0), .sel(busy), .out(tgt_req_we));
    Mux2 #(1) u_mux2_rsp(.in0(req_rsp), .in1(1'b1), .sel(busy), .out(tgt_req_rsp));
    Mux2 #(ADDR_WIDTH) u_mux2_addr(.in0(req_addr), .in1(beat_addr), .sel(busy),
                                   .out(tgt_req_addr));
    Mux2 #(3) u_mux2_size(.in0(req_size), .in1(size_q), .sel(busy), .out(tgt_req_size));
    Mux2 #(FIELDS_WIDTH) u_mux2_fields(.in0(req_fields), .in1(fields_q), .sel(busy),
                                       .out(tgt_req_fields));

    // See the behave version.
    `DC_ASSERT(a_burst_is_read, !(req_valid && burst && (req_we || !req_rsp)))
    `DC_ASSERT_NEXT(a_beats_follow, start, busy && tgt_req_valid)

endmodule

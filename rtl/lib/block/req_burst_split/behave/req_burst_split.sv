/* Request burst splitter: a burst read on a request channel goes out as its single beats to
 * a target that takes no bursts; behavioral.
 *
 * The channel is the library's: requests on valid/ready, a request with req_rsp answered
 * req_len + 1 times in order (kb rtl/lib/block/bursts), one or more clocks after its target
 * took it, with no ready. A burst read (req_len L above 0) goes to the target as L + 1
 * requests of one beat each, at req_addr + (k << req_size) for beat k (AXI's INCR burst),
 * one a clock while the target is ready. The target answers each beat in order, so its
 * answers are the burst's L + 1 answers as they are: the block has no answer path, the
 * caller wires the target's answers straight back to the requester.
 *
 * The burst is taken with its first beat, in the clock the target takes beat 0 (req_ready is
 * the target's ready while idle), and its address, size, length and other fields are kept
 * for the beats after (busy, req_ready 0). A requester's own records (a ReqDemux's or a
 * ReqMux's count and owner) are thus made in the clock beat 0 goes out, before any answer
 * can come; were the burst taken with its last beat, the answers to the first beats would
 * come back before the requester counted the burst (kb rtl/lib/block/req_burst_split/
 * design). A single beat passes as wires: never busy. The next request's first beat goes in
 * the clock after a burst's last, so beats flow one a clock.
 *
 * Writes: the channel carries one wdata a request, so a write is never a burst (a_burst_is_
 * read); writes and other single beats pass unchanged. The fields (FIELDS_WIDTH bits: data,
 * strobes, an atomic's operation, ...) go with every beat.
 *
 *   idle:  req --------------------------------------------> tgt   (beat 0, wires)
 *          taken with req_len > 0 --> copy, busy, k = 1
 *   busy:  copy: addr + (k << size), size, fields ---------> tgt   (beats 1 .. len, reads)
 *          req_ready 0;  beat len taken --> idle
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
    // @kb: rtl/lib/block/bursts
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

    logic                    busy;      // beats 1 .. len_q of a burst go out from the copy
    logic [LEN_WIDTH-1:0]    k;         // the number of the beat out while busy
    logic [ADDR_WIDTH-1:0]   addr_q;    // the copy: beat 0's address,
    logic [2:0]              size_q;    //   the beats' size,
    logic [LEN_WIDTH-1:0]    len_q;     //   beats - 1,
    logic [FIELDS_WIDTH-1:0] fields_q;  //   the other fields
    logic                    take;      // the requester's request is taken (its beat 0)
    logic                    tgt_take;  // the target takes a beat
    logic                    last;      // ... the burst's last

    // @kb: rtl/lib/block/req_burst_split/design
    // Idle: the request itself, beat 0. Busy: the copy's next beat, a read.
    assign tgt_req_valid  = busy || req_valid;
    assign req_ready      = !busy && tgt_req_ready;
    assign tgt_req_we     = busy ? 1'b0 : req_we;
    assign tgt_req_rsp    = busy ? 1'b1 : req_rsp;
    assign tgt_req_addr   = busy ? addr_q + (ADDR_WIDTH'(k) << size_q) : req_addr;
    assign tgt_req_size   = busy ? size_q : req_size;
    assign tgt_req_fields = busy ? fields_q : req_fields;

    assign take     = req_valid && req_ready;
    assign tgt_take = tgt_req_valid && tgt_req_ready;
    assign last     = k == len_q;

    always_ff @(posedge clk)
        if (!rst_n)
            busy <= 1'b0;
        else if (take && req_len != '0)
            busy <= 1'b1;
        else if (busy && tgt_take && last)
            busy <= 1'b0;

    always_ff @(posedge clk)
        if (take) begin
            k        <= LEN_WIDTH'(1);
            addr_q   <= req_addr;
            size_q   <= req_size;
            len_q    <= req_len;
            fields_q <= req_fields;
        end else if (busy && tgt_take)
            k <= k + 1'b1;

    // Only a read is a burst; after a burst is taken, its next beat is offered.
    `DC_ASSERT(a_burst_is_read, !(req_valid && req_len != '0 && (req_we || !req_rsp)))
    `DC_ASSERT_NEXT(a_beats_follow, take && req_len != '0, busy && tgt_req_valid)

endmodule

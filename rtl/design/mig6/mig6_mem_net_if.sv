/* The shared memory's network interface: request packets from the PEs as requests to the
 * memory, its answers back as answer packets (Mig6NocPkg; rtl/design/mig6/README.md); the
 * exclusive monitor of LR and SC.
 *
 * On the memory side it is the requester of a library request channel, a word wide, to
 * AtomicUnit in front of a RAM: requests on valid/ready, one with mem_req_rsp (a read, an
 * atomic) answered by mem_rsp_valid in order, one or more clocks after it was taken, with no
 * ready (every answer is taken), a write without an answer; single beats only. A CBO is
 * taken and dropped: nothing caches the shared memory.
 *
 * Request flits wait in a buffer of BUF_DEPTH flits (the credits the router starts with); a
 * flit leaving it sends a credit back. A head with a body is kept (head_q) until its body
 * is at the front; the request goes on with its body to a ReqBurstSplit, which takes it with
 * its first beat (the buffer pops then) and sends a burst READ (len above 0) as its words,
 * one a clock (kb rtl/lib/block/req_burst_split/design). Answers have no ready, so a beat
 * that is answered goes to the memory only when its answer has a place: owed, the answers
 * not yet sent (the beats in the memory, in_mem, and the answers waiting for a credit,
 * answer FIFO), must be below D = 1 << PENDING_WIDTH; the gate holds a beat as a target not
 * ready would. A burst of any length passes D's room a word at a time. While owed is D the
 * requests wait in the buffer, the buffer fills, the router gets no credits, and the wait
 * spreads back to the PEs as backpressure; the answers drain on their own network, so owed
 * falls again.
 *
 * Answers: the src FIFO keeps, for each answered request in the memory, its src and len.
 * Each word the memory answers goes into the answer FIFO as one flit: the request's first
 * word a head (the route to its src, RSP_DATA, the word), the next ones body flits, the last
 * one a tail; the flits leave one a clock while the answer network's local input has a credit
 * (a count from BUF_DEPTH). A burst's head leaves as soon as its first word is there, its
 * body flits as theirs come (cut-through, user's choice 2026-11-23): the words of one burst
 * come in order with no other answer between them, and the answer network has this one
 * source, so a pause inside a packet holds no path another packet needs. With more sources
 * on the answer network (other PEs' memories), send a packet only once its words are in, in
 * packets of a bounded size (kb rtl/design/mig6/bursts).
 *
 * LR and SC (kb rtl/design/mig6/far_lr_sc): the reservations are the library's
 * ExclusiveMonitor's, one per PE (its src: PE y * MESH_X + x), a word each; this block
 * calls it as the memory takes requests (single beats: a request's take is its beat's). An
 * LR goes to the memory as a READ and reserves its word when the memory takes it; a WRITE,
 * an ATOMIC or a successful SC the memory takes is a write for the monitor (every
 * reservation of its word ends). An SC is decided at the front, with its body, when no
 * answer is in the memory (src FIFO empty, as AtomicUnit waits with an atomic): it succeeds
 * when the monitor says so (sc_ok), and the memory takes it as a WRITE (no answer from
 * there); it fails and goes nowhere. Either way its ACK, the status, goes into the answer
 * FIFO behind every answer before it, and the monitor ends its PE's reservation (sc_done).
 *
 *   request network --> buffer --> head_q (a head with a body) --> ReqBurstSplit (beats)
 *                         \-- credit back as a flit leaves          --> owed < D --> mem_req
 *                                 u_monitor: LR reserves, writes and SC end
 *   split take --> src FIFO {src, len} (READ, LR, ATOMIC)
 *   mem_rsp --> answer FIFO {head: first word, tail: last word, flit} --> answer network
 *   SC decided --> answer FIFO {head, tail, route: its src, RSP_ACK, SC_SUCCESS or SC_FAIL}
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "dark_circuit_assert.svh"

module Mig6MemNetIf import Mig6NocPkg::*; #(
    parameter BUF_DEPTH     = 4,    // the input buffer, and the router's: credits both ways
    parameter PENDING_WIDTH = 2     // D = 1 << PENDING_WIDTH answers owed at most
)(
    input  wire                   clk,
    input  wire                   rst_n,            // synchronous reset, active low
    // The request network's local output, the answer network's local input
    input  req_link_fwd_t         noc_req_fwd,      // requests from the router
    output link_bwd_t             noc_req_bwd,      // credits to it
    output rsp_link_fwd_t         noc_rsp_fwd,      // answers to the router
    // A credit's vc is not read: one VC.
    /* verilator lint_off UNUSEDSIGNAL */
    input  link_bwd_t             noc_rsp_bwd,      // credits from it
    /* verilator lint_on UNUSEDSIGNAL */
    // Memory side: the requester of a request channel
    output logic                  mem_req_valid,
    input  wire                   mem_req_ready,
    output logic                  mem_req_we,
    output logic                  mem_req_rsp,      // wants an answer: a read, an atomic
    output logic [ADDR_WIDTH-1:0] mem_req_addr,     // byte address
    output logic [SIZE_WIDTH-1:0] mem_req_size,     // 1 << mem_req_size bytes
    output AtomicPkg::atop_t      mem_req_atop,     // ATOP_NONE, or an atomic operation
    output logic [DATA_WIDTH-1:0] mem_req_wdata,    // write data, an atomic's operand
    output logic [STRB_WIDTH-1:0] mem_req_wstrb,
    input  wire                   mem_rsp_valid,    // the answer to a read or an atomic
    input  wire  [DATA_WIDTH-1:0] mem_rsp_data
);
    // FifoT holds a power of 2 entries, at least 2: BUF_DEPTH rounded up.
    localparam BUF_ADDR_WIDTH = (BUF_DEPTH > 1) ? $clog2(BUF_DEPTH) : 1;
    localparam CREDIT_WIDTH   = $clog2(BUF_DEPTH + 1);
    localparam D              = 1 << PENDING_WIDTH;
    localparam WORD_START     = $clog2(STRB_WIDTH);         // a word: 1 << WORD_START bytes
    localparam PE_WIDTH       = (N_PES > 1) ? $clog2(N_PES) : 1;
    localparam FW             = $bits(AtomicPkg::atop_t) + DATA_WIDTH + STRB_WIDTH;

    `DC_STATIC_ASSERT(a_sizes, BUF_DEPTH >= 1 && PENDING_WIDTH >= 1)

    typedef struct packed {
        logic [X_WIDTH-1:0] x;
        logic [Y_WIDTH-1:0] y;
    } node_t;

    // An answered request in the memory: where its answer goes, its words - 1.
    typedef struct packed {
        node_t                src;
        logic [LEN_WIDTH-1:0] len;
    } owed_t;

    // An answer flit waiting for a credit.
    typedef struct packed {
        logic                      head;
        logic                      tail;
        logic [RSP_DATA_WIDTH-1:0] data;    // rsp_t (a head) or rsp_body_t
    } out_t;

    // Bits not read: a flit's vc (one VC), a head's route (here), the bodies' zero bits, a
    // head's cmo (a CBO is dropped).
    /* verilator lint_off UNUSEDSIGNAL */
    req_flit_t                front;        // the buffer's oldest flit
    req_head_t                front_head;
    req_write_t               write_body;
    req_atomic_t              atomic_body;
    req_rest_t                cur;          // the request at the front: its head's fields
    /* verilator lint_on UNUSEDSIGNAL */
    logic                     buf_empty;
    req_rest_t                front_rest;
    req_rest_t                head_q;       // a head whose body is not yet at the front
    logic                     have_head_q;
    logic                     mem_answers;  // answered by the memory (READ, LR, ATOMIC)
    logic [PENDING_WIDTH:0]   in_mem;       // beats in the memory whose answers are not back
    logic [PENDING_WIDTH:0]   rsp_count;
    logic [PENDING_WIDTH+1:0] owed;         // answers not yet sent
    logic                     room;
    logic                     whole;        // the request is at the front with its body
    logic                     capture;      // a head with a body goes into head_q
    logic                     drop;         // a CBO is taken and dropped
    logic                     pop;          // a flit leaves the buffer
    // The request to ReqBurstSplit, its beats to the memory.
    logic                     split_valid;
    logic                     split_ready;
    logic                     split_take;   // the request is taken (with its first beat)
    logic                     split_we;
    AtomicPkg::atop_t         split_atop;
    logic [DATA_WIDTH-1:0]    split_wdata;
    logic [STRB_WIDTH-1:0]    split_wstrb;
    logic                     beat_valid;   // ReqBurstSplit offers a beat
    logic                     beat_ready;
    logic [FW-1:0]            beat_fields;
    logic                     gate;         // the beat's answer has a place, or none comes
    logic                     beat_taken;   // the memory takes a beat
    // Answers.
    owed_t                    owed_front;   // the oldest answered request in the memory
    logic                     src_empty;
    logic [LEN_WIDTH-1:0]     word_q;       // the number of its next word
    logic                     first_word;
    logic                     last_word;
    rsp_t                     rsp_head;     // an answer's head flit
    rsp_rest_t                rsp_rest;
    rsp_body_t                rsp_body;     // ... or body flit
    out_t                     out_in;
    out_t                     out_front;    // the oldest answer flit waiting for a credit
    logic                     rsp_empty;
    logic                     send;         // an answer flit goes out
    logic [CREDIT_WIDTH-1:0]  credits_q;    // free slots of the router's buffer
    // LR and SC
    logic [PE_WIDTH-1:0]      cur_pe;       // the request's PE
    logic                     sc_ready;     // an SC at the front may be decided now
    logic                     sc_ok;        // its PE's reservation holds (the monitor)
    logic                     sc_fail;      // a failing SC is decided: it goes nowhere
    logic                     sc_ack;       // an SC is decided: its ACK goes into the FIFO
    logic                     writes;       // the memory takes a write
    logic                     reserves;     // the memory takes an LR
    // Status the counts make unnecessary (full is only checked).
    /* verilator lint_off UNUSEDSIGNAL */
    logic                     buf_full;
    logic [BUF_ADDR_WIDTH:0]  buf_count;
    logic                     buf_almost_full;
    logic                     buf_almost_empty;
    logic                     src_full;
    logic [PENDING_WIDTH:0]   src_count;
    logic                     src_almost_full;
    logic                     src_almost_empty;
    logic                     rsp_full;
    logic                     rsp_almost_full;
    logic                     rsp_almost_empty;
    /* verilator lint_on UNUSEDSIGNAL */

    // Request flits as they come; the router sends one only with a credit, so never when full.
    FifoT #(.T(req_flit_t), .ADDR_WIDTH(BUF_ADDR_WIDTH)) u_req_buf(
        .clk, .rst_n, .write(noc_req_fwd.valid), .data_in(noc_req_fwd.flit), .read(pop),
        .data_out(front), .empty(buf_empty), .full(buf_full), .count(buf_count),
        .almost_full(buf_almost_full), .almost_empty(buf_almost_empty));

    assign front_head  = front.data;
    assign front_rest  = front_head.rest;
    assign write_body  = front.data;
    assign atomic_body = front.data;

    // The request at the front: a head alone, or head_q with its body at the front.
    assign cur         = have_head_q ? head_q : front_rest;
    assign mem_answers = cur.op == REQ_READ || cur.op == REQ_LR || cur.op == REQ_ATOMIC;
    assign owed        = (PENDING_WIDTH + 2)'(in_mem) + (PENDING_WIDTH + 2)'(rsp_count);
    assign room        = owed < (PENDING_WIDTH + 2)'(D);
    assign whole       = !buf_empty && (have_head_q || !req_has_body(cur.op));

    // The SC at the front, with its body, when no answer is in the memory.
    // @kb: rtl/design/mig6/far_lr_sc
    assign cur_pe   = PE_WIDTH'(cur.src_y * MESH_X + cur.src_x);
    assign sc_ready = whole && cur.op == REQ_SC && src_empty && room;
    assign sc_fail  = sc_ready && !sc_ok;

    assign capture     = !buf_empty && !have_head_q && req_has_body(cur.op);
    assign drop        = !buf_empty && !have_head_q && cur.op == REQ_CBO;
    assign split_valid = whole && cur.op != REQ_CBO && (cur.op != REQ_SC || (sc_ready && sc_ok));
    assign split_take  = split_valid && split_ready;
    assign pop         = capture || drop || split_take || sc_fail;
    assign sc_ack      = (split_take && cur.op == REQ_SC) || sc_fail;

    assign noc_req_bwd.valid = pop;
    assign noc_req_bwd.vc    = '0;

    always_ff @(posedge clk)
        if (!rst_n)
            have_head_q <= 1'b0;
        else if (capture) begin
            have_head_q <= 1'b1;
            head_q      <= front_rest;
        end else if (split_take || sc_fail)
            have_head_q <= 1'b0;

    // The request: the head's address, size and len, the body's data or operand. A
    // successful SC is a WRITE at the memory; an LR a READ; a burst READ its words.
    // @kb: rtl/lib/block/req_burst_split/design
    assign split_we    = cur.op == REQ_WRITE || cur.op == REQ_SC;
    assign split_atop  = (cur.op == REQ_ATOMIC) ? atomic_body.atop : AtomicPkg::ATOP_NONE;
    assign split_wdata = (cur.op == REQ_ATOMIC) ? atomic_body.operand
                       : split_we               ? write_body.data : '0;
    assign split_wstrb = split_we ? write_body.strb : '0;

    ReqBurstSplit #(.ADDR_WIDTH(ADDR_WIDTH), .FIELDS_WIDTH(FW), .LEN_WIDTH(LEN_WIDTH))
        u_burst_split(
        .clk, .rst_n,
        .req_valid(split_valid), .req_ready(split_ready), .req_we(split_we),
        .req_rsp(mem_answers), .req_len(cur.len), .req_addr(cur.addr), .req_size(cur.size),
        .req_fields({split_atop, split_wdata, split_wstrb}),
        .tgt_req_valid(beat_valid), .tgt_req_ready(beat_ready), .tgt_req_we(mem_req_we),
        .tgt_req_rsp(mem_req_rsp), .tgt_req_addr(mem_req_addr), .tgt_req_size(mem_req_size),
        .tgt_req_fields(beat_fields));
    assign {mem_req_atop, mem_req_wdata, mem_req_wstrb} = beat_fields;

    // A beat that is answered goes on only while its answer has a place (owed below D).
    assign gate          = room || !mem_req_rsp;
    assign mem_req_valid = beat_valid && gate;
    assign beat_ready    = mem_req_ready && gate;
    assign beat_taken    = mem_req_valid && mem_req_ready;

    always_ff @(posedge clk)
        if (!rst_n)
            in_mem <= '0;
        else
            in_mem <= in_mem + (PENDING_WIDTH + 1)'(beat_taken && mem_req_rsp)
                             - (PENDING_WIDTH + 1)'(mem_rsp_valid);

    // The reservations: an LR the memory takes reserves its word for its PE; a write the
    // memory takes ends every reservation of its word; a decided SC its PE's. A request's take
    // is its first beat's, at the memory in the same clock.
    // @kb: rtl/lib/block/atomic/exclusive_monitor/design
    assign writes   = split_take && (cur.op == REQ_WRITE || cur.op == REQ_ATOMIC ||
                                     cur.op == REQ_SC);
    assign reserves = split_take && cur.op == REQ_LR;

    ExclusiveMonitor #(.N_AGENTS(N_PES), .ADDR_WIDTH(ADDR_WIDTH), .RESV_OFFSET(WORD_START))
        u_monitor(
        .clk, .rst_n,
        .reserve(reserves), .reserve_agent(cur_pe), .reserve_addr(cur.addr),
        .write(writes), .write_addr(cur.addr),
        .sc_agent(cur_pe), .sc_addr(cur.addr), .sc_ok, .sc_done(sc_ack));

    // Where each answered request's words go, and how many, in the order of the requests;
    // the oldest leaves with its last word.
    FifoT #(.T(owed_t), .ADDR_WIDTH(PENDING_WIDTH)) u_src_fifo(
        .clk, .rst_n, .write(split_take && mem_answers),
        .data_in({cur.src_x, cur.src_y, cur.len}), .read(mem_rsp_valid && last_word),
        .data_out(owed_front), .empty(src_empty), .full(src_full), .count(src_count),
        .almost_full(src_almost_full), .almost_empty(src_almost_empty));

    assign first_word = word_q == '0;
    assign last_word  = word_q == owed_front.len;

    always_ff @(posedge clk)
        if (!rst_n)
            word_q <= '0;
        else if (mem_rsp_valid)
            word_q <= last_word ? '0 : word_q + 1'b1;

    // @kb: rtl/design/mig6/bursts
    // The answer flits, until the answer network has room: the memory's words (the first a
    // head, the next body flits, the last a tail), or an SC's ACK (never in the same clock:
    // an SC is decided only with nothing in memory).
    assign rsp_rest.op     = sc_ack ? RSP_ACK : RSP_DATA;
    assign rsp_rest.data   = sc_ack ? (sc_ok ? SC_SUCCESS : SC_FAIL) : mem_rsp_data;
    assign rsp_head.dest_x = sc_ack ? cur.src_x : owed_front.src.x;
    assign rsp_head.dest_y = sc_ack ? cur.src_y : owed_front.src.y;
    assign rsp_head.rest   = rsp_rest;
    assign rsp_body.zero   = '0;
    assign rsp_body.data   = mem_rsp_data;
    assign out_in.head     = sc_ack || first_word;
    assign out_in.tail     = sc_ack || last_word;
    assign out_in.data     = (sc_ack || first_word) ? rsp_head : rsp_body;

    FifoT #(.T(out_t), .ADDR_WIDTH(PENDING_WIDTH)) u_rsp_fifo(
        .clk, .rst_n, .write(mem_rsp_valid || sc_ack), .data_in(out_in), .read(send),
        .data_out(out_front), .empty(rsp_empty), .full(rsp_full), .count(rsp_count),
        .almost_full(rsp_almost_full), .almost_empty(rsp_almost_empty));

    assign send                  = !rsp_empty && credits_q != '0;
    assign noc_rsp_fwd.valid     = send;
    assign noc_rsp_fwd.flit.head = out_front.head;
    assign noc_rsp_fwd.flit.tail = out_front.tail;
    assign noc_rsp_fwd.flit.vc   = '0;
    assign noc_rsp_fwd.flit.data = out_front.data;

    always_ff @(posedge clk)
        if (!rst_n) credits_q <= CREDIT_WIDTH'(BUF_DEPTH);
        else        credits_q <= credits_q - CREDIT_WIDTH'(send) + CREDIT_WIDTH'(noc_rsp_bwd.valid);

    // A packet is a head, then its body when it has one.
    `DC_ASSERT(a_head_first, !(!buf_empty && !have_head_q && !front.head))
    `DC_ASSERT(a_body_follows, !(!buf_empty && have_head_q && (front.head || !front.tail)))
    // Credits keep the buffer from overflowing; owed < D keeps both FIFOs from it.
    `DC_ASSERT(a_buf_room, !(noc_req_fwd.valid && buf_full))
    `DC_ASSERT(a_src_room, !(split_take && mem_answers && src_full))
    `DC_ASSERT(a_rsp_room, !((mem_rsp_valid || sc_ack) && rsp_full))
    `DC_ASSERT(a_owed_at_most_d, owed <= (PENDING_WIDTH + 2)'(D))
    // The memory answers only what was asked; an SC's ACK never meets one of its answers.
    `DC_ASSERT(a_answer_expected, !(mem_rsp_valid && (src_empty || in_mem == '0)))
    `DC_ASSERT(a_sc_alone, !(mem_rsp_valid && sc_ack))
    // Only a READ is a burst; an LR or an SC is a word, its src a PE of the mesh.
    // @kb: rtl/lib/block/bursts
    `DC_ASSERT(a_burst_read, !(whole && !req_len_ok(cur.op, cur.len)))
    `DC_ASSERT(a_excl_word, !(whole && (cur.op == REQ_LR || cur.op == REQ_SC) &&
                              (cur.size != SIZE_WIDTH'(WORD_START) ||
                               cur.addr[WORD_START-1:0] != '0 || cur.src_x >= MESH_X ||
                               cur.src_y >= MESH_Y)))
    // The router returns no more credits than it has slots.
    `DC_ASSERT(a_credits_at_most_depth,
               !(noc_rsp_bwd.valid && !send && credits_q == CREDIT_WIDTH'(BUF_DEPTH)))

endmodule

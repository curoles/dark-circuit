/* The shared memory's network interface: request packets from the PEs as requests to the
 * memory, its answers back as answer packets (Mig6NocPkg; rtl/design/mig6/README.md); the
 * exclusive monitor of LR and SC.
 *
 * On the memory side it is the requester of a library request channel, a word wide, to
 * AtomicUnit in front of a RAM: requests on valid/ready, one with mem_req_rsp (a read, an
 * atomic) answered by mem_rsp_valid in order, one or more clocks after it was taken, with no
 * ready (every answer is taken), a write without an answer. A CBO is taken and dropped:
 * nothing caches the shared memory.
 *
 * Request flits wait in a buffer of BUF_DEPTH flits (the credits the router starts with); a
 * flit leaving it sends a credit back. A head with a body is kept (head_q) until its body
 * is at the front; the request goes to the memory with its body. Answers have no ready, so
 * a request that is answered (READ, LR, ATOMIC, SC) is taken only when its answer has a
 * place: owed, the answers not yet sent (the requests in the memory, src FIFO, and the
 * answers waiting for a credit, answer FIFO), must be below D = 1 << PENDING_WIDTH. Then
 * both FIFOs always have room; while owed is D the request waits in the buffer, the buffer
 * fills, the router gets no credits, and the wait spreads back to the PEs as backpressure.
 * The answers drain on their own network, so owed falls again. An answer goes to the src
 * of its request (the src FIFO: the answers come in order) as one flit while the answer
 * network's local input has a credit (a count from BUF_DEPTH).
 *
 * The exclusive monitor (kb rtl/design/mig6/far_lr_sc), as AXI's at a memory: a
 * reservation per PE (its src: PE y * MESH_X + x), valid and the address of a word. An LR
 * goes to the memory as a READ and reserves its word for its PE when the memory takes it.
 * Any WRITE, ATOMIC or successful SC to a word ends every reservation of that word, the
 * writer's own too (the spec allows it: a constrained LR/SC loop has no store). An SC is
 * decided at the front, with its body, when no answer is in the memory (src FIFO empty, as
 * AtomicUnit waits with an atomic): its PE's reservation holds (valid, same word) or not.
 * It succeeds: the memory takes it as a WRITE (no answer from there); it fails: it goes
 * nowhere. Either way its ACK, the status, goes into the answer FIFO behind every answer
 * before it, and its PE's reservation ends.
 *
 *   request network --> buffer --> head_q (a head with a body) --> mem_req (owed < D)
 *                         \-- credit back as a flit leaves      \-> src FIFO (READ, LR, ATOMIC)
 *                                         monitor: LR reserves, writes and SC end
 *   mem_rsp --> answer FIFO {route: src FIFO's oldest, RSP_DATA, data} --> answer network
 *   SC decided --> answer FIFO {route: its src, RSP_ACK, SC_SUCCESS or SC_FAIL}
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
    localparam WORD_START     = $clog2(STRB_WIDTH);         // a word's address bits start here
    localparam PE_WIDTH       = (N_PES > 1) ? $clog2(N_PES) : 1;

    `DC_STATIC_ASSERT(a_sizes, BUF_DEPTH >= 1 && PENDING_WIDTH >= 1)

    typedef struct packed {
        logic [X_WIDTH-1:0] x;
        logic [Y_WIDTH-1:0] y;
    } node_t;

    typedef logic [ADDR_WIDTH-1:WORD_START] word_addr_t;

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
    logic                     needs_slot;   // an answered request: an answer is owed
    logic                     mem_answers;  // ... answered by the memory (READ, LR, ATOMIC)
    logic [PENDING_WIDTH:0]   src_count;
    logic [PENDING_WIDTH:0]   rsp_count;
    logic [PENDING_WIDTH+1:0] owed;         // answers not yet sent
    logic                     room;
    logic                     whole;        // the request is at the front with its body
    logic                     capture;      // a head with a body goes into head_q
    logic                     drop;         // a CBO is taken and dropped
    logic                     taken;        // the memory takes the request
    logic                     pop;          // a flit leaves the buffer
    node_t                    src_front;    // the oldest request's src: the answer's route
    logic                     src_empty;
    rsp_t                     rsp_in;       // an answer, with its route
    rsp_rest_t                rsp_rest;
    rsp_t                     rsp_front;    // the oldest answer waiting for a credit
    logic                     rsp_empty;
    logic                     send;         // an answer flit goes out
    logic [CREDIT_WIDTH-1:0]  credits_q;    // free slots of the router's buffer
    // The exclusive monitor
    logic [N_PES-1:0]         resv_valid;   // PE p's reservation holds
    word_addr_t               resv_addr [N_PES];    // ... of this word
    logic [PE_WIDTH-1:0]      cur_pe;       // the request's PE
    word_addr_t               cur_word;     // its word
    logic                     sc_ready;     // an SC at the front may be decided now
    logic                     sc_ok;        // its PE's reservation holds
    logic                     sc_fail;      // a failing SC is decided: it goes nowhere
    logic                     sc_ack;       // an SC is decided: its ACK goes into the FIFO
    logic                     writes;       // the memory takes a write of cur_word
    logic                     reserves;     // the memory takes an LR
    // Status the counts make unnecessary (full is only checked).
    /* verilator lint_off UNUSEDSIGNAL */
    logic                     buf_full;
    logic [BUF_ADDR_WIDTH:0]  buf_count;
    logic                     buf_almost_full;
    logic                     buf_almost_empty;
    logic                     src_full;
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
    assign needs_slot  = req_answered(cur.op);
    assign mem_answers = cur.op == REQ_READ || cur.op == REQ_LR || cur.op == REQ_ATOMIC;
    assign owed        = (PENDING_WIDTH + 2)'(src_count) + (PENDING_WIDTH + 2)'(rsp_count);
    assign room        = owed < (PENDING_WIDTH + 2)'(D);
    assign whole       = !buf_empty && (have_head_q || !req_has_body(cur.op));

    // The SC at the front, with its body, when no answer is in the memory.
    // @kb: rtl/design/mig6/far_lr_sc
    assign cur_pe   = PE_WIDTH'(cur.src_y * MESH_X + cur.src_x);
    assign cur_word = cur.addr[ADDR_WIDTH-1:WORD_START];
    assign sc_ready = whole && cur.op == REQ_SC && src_empty && room;
    assign sc_ok    = resv_valid[cur_pe] && resv_addr[cur_pe] == cur_word;
    assign sc_fail  = sc_ready && !sc_ok;

    assign capture = !buf_empty && !have_head_q && req_has_body(cur.op);
    assign drop    = !buf_empty && !have_head_q && cur.op == REQ_CBO;
    assign mem_req_valid = whole && cur.op != REQ_CBO && (room || !needs_slot)
                           && (cur.op != REQ_SC || (sc_ready && sc_ok));
    assign taken   = mem_req_valid && mem_req_ready;
    assign pop     = capture || drop || taken || sc_fail;
    assign sc_ack  = (taken && cur.op == REQ_SC) || sc_fail;

    assign noc_req_bwd.valid = pop;
    assign noc_req_bwd.vc    = '0;

    always_ff @(posedge clk)
        if (!rst_n)
            have_head_q <= 1'b0;
        else if (capture) begin
            have_head_q <= 1'b1;
            head_q      <= front_rest;
        end else if (taken || sc_fail)
            have_head_q <= 1'b0;

    // The request to the memory: the head's address and size, the body's data or operand.
    // A successful SC is a WRITE there; an LR a READ.
    assign mem_req_we    = cur.op == REQ_WRITE || cur.op == REQ_SC;
    assign mem_req_rsp   = mem_answers;
    assign mem_req_addr  = cur.addr;
    assign mem_req_size  = cur.size;
    assign mem_req_atop  = (cur.op == REQ_ATOMIC) ? atomic_body.atop : AtomicPkg::ATOP_NONE;
    assign mem_req_wdata = (cur.op == REQ_ATOMIC) ? atomic_body.operand
                         : mem_req_we             ? write_body.data : '0;
    assign mem_req_wstrb = mem_req_we ? write_body.strb : '0;

    // The monitor: a write of a word ends every reservation of it; a decided SC its PE's; an
    // LR the memory takes reserves its word for its PE.
    assign writes   = taken && (cur.op == REQ_WRITE || cur.op == REQ_ATOMIC || cur.op == REQ_SC);
    assign reserves = taken && cur.op == REQ_LR;

    always_ff @(posedge clk)
        if (!rst_n)
            resv_valid <= '0;
        else
            for (int p = 0; p < N_PES; p++)
                if (reserves && int'(cur_pe) == p)
                    resv_valid[p] <= 1'b1;
                else if ((writes && resv_addr[p] == cur_word) || (sc_ack && int'(cur_pe) == p))
                    resv_valid[p] <= 1'b0;

    always_ff @(posedge clk)
        if (reserves)
            resv_addr[cur_pe] <= cur_word;

    // Where each answer the memory owes goes, in the order of the requests.
    FifoT #(.T(node_t), .ADDR_WIDTH(PENDING_WIDTH)) u_src_fifo(
        .clk, .rst_n, .write(taken && mem_answers), .data_in({cur.src_x, cur.src_y}),
        .read(mem_rsp_valid), .data_out(src_front), .empty(src_empty), .full(src_full),
        .count(src_count), .almost_full(src_almost_full), .almost_empty(src_almost_empty));

    // The answers, with their route, until the answer network has room: the memory's, or
    // an SC's ACK (never in the same clock: an SC is decided only with nothing in memory).
    assign rsp_rest.op   = sc_ack ? RSP_ACK : RSP_DATA;
    assign rsp_rest.data = sc_ack ? (sc_ok ? SC_SUCCESS : SC_FAIL) : mem_rsp_data;
    assign rsp_in.dest_x = sc_ack ? cur.src_x : src_front.x;
    assign rsp_in.dest_y = sc_ack ? cur.src_y : src_front.y;
    assign rsp_in.rest   = rsp_rest;

    FifoT #(.T(rsp_t), .ADDR_WIDTH(PENDING_WIDTH)) u_rsp_fifo(
        .clk, .rst_n, .write(mem_rsp_valid || sc_ack), .data_in(rsp_in), .read(send),
        .data_out(rsp_front), .empty(rsp_empty), .full(rsp_full), .count(rsp_count),
        .almost_full(rsp_almost_full), .almost_empty(rsp_almost_empty));

    assign send                  = !rsp_empty && credits_q != '0;
    assign noc_rsp_fwd.valid     = send;
    assign noc_rsp_fwd.flit.head = 1'b1;
    assign noc_rsp_fwd.flit.tail = 1'b1;
    assign noc_rsp_fwd.flit.vc   = '0;
    assign noc_rsp_fwd.flit.data = rsp_front;

    always_ff @(posedge clk)
        if (!rst_n) credits_q <= CREDIT_WIDTH'(BUF_DEPTH);
        else        credits_q <= credits_q - CREDIT_WIDTH'(send) + CREDIT_WIDTH'(noc_rsp_bwd.valid);

    // A packet is a head, then its body when it has one.
    `DC_ASSERT(a_head_first, !(!buf_empty && !have_head_q && !front.head))
    `DC_ASSERT(a_body_follows, !(!buf_empty && have_head_q && (front.head || !front.tail)))
    // Credits keep the buffer from overflowing; owed < D keeps both FIFOs from it.
    `DC_ASSERT(a_buf_room, !(noc_req_fwd.valid && buf_full))
    `DC_ASSERT(a_src_room, !(taken && mem_answers && src_full))
    `DC_ASSERT(a_rsp_room, !((mem_rsp_valid || sc_ack) && rsp_full))
    `DC_ASSERT(a_owed_at_most_d, owed <= (PENDING_WIDTH + 2)'(D))
    // The memory answers only what was asked; an SC's ACK never meets one of its answers.
    `DC_ASSERT(a_answer_expected, !(mem_rsp_valid && src_empty))
    `DC_ASSERT(a_sc_alone, !(mem_rsp_valid && sc_ack))
    // An LR or an SC is a word, its src a PE of the mesh.
    `DC_ASSERT(a_excl_word, !(whole && (cur.op == REQ_LR || cur.op == REQ_SC) &&
                              (cur.size != SIZE_WIDTH'(WORD_START) ||
                               cur.addr[WORD_START-1:0] != '0 || cur.src_x >= MESH_X ||
                               cur.src_y >= MESH_Y)))
    // The router returns no more credits than it has slots.
    `DC_ASSERT(a_credits_at_most_depth,
               !(noc_rsp_bwd.valid && !send && credits_q == CREDIT_WIDTH'(BUF_DEPTH)))

endmodule

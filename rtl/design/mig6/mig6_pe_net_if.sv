/* A PE's network interface: the PE's requests to the shared memory as request packets, their
 * answers back (Mig6NocPkg; rtl/design/mig6/README.md).
 *
 * On the PE side it is the target of a library request channel, a word wide: requests on
 * valid/ready (an offer not taken stays the same), a read or an atomic answered by
 * rsp_valid in order (no ready: every answer is taken), a write or a CBO without an answer.
 * The opcode: a CBO when cmo is not CMO_NONE (a write without strobes), else an ATOMIC when
 * atop is not ATOP_NONE (a read with an operand), else a WRITE when we, else a READ. A
 * request goes out as its head, then its body (WRITE, ATOMIC), a flit a clock while the
 * request network's local input has a credit (a count from BUF_DEPTH, the router's buffer);
 * the request is taken (req_ready) with its last flit. An answer from the answer network
 * goes straight to rsp_valid and its credit straight back: it holds no answer, so it
 * limits nothing; a requester does (a ReqMux's pending FIFO).
 *
 *   req --> op_of --> head: route MEM_X, MEM_Y; src MY_X, MY_Y --+--> request network
 *                \--> body (WRITE, ATOMIC), after the head ------+    (body_q)
 *   rsp <-- the answer's data <-- answer network, its credit back at once
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "dark_circuit_assert.svh"

module Mig6PeNetIf import Mig6NocPkg::*; #(
    parameter logic [X_WIDTH-1:0] MY_X      = '0,   // this PE's node: the answers' route
    parameter logic [Y_WIDTH-1:0] MY_Y      = '0,
    parameter                     BUF_DEPTH = 4     // the router's input buffer: credits
)(
    input  wire                   clk,
    input  wire                   rst_n,            // synchronous reset, active low
    // PE side: the target of a request channel
    input  wire                   req_valid,
    output logic                  req_ready,        // taken with the request's last flit
    input  wire                   req_we,
    input  wire [ADDR_WIDTH-1:0]  req_addr,         // byte address
    input  wire [SIZE_WIDTH-1:0]  req_size,         // 1 << req_size bytes, a word at most
    input  AtomicPkg::atop_t      req_atop,         // ATOP_NONE, or an atomic operation
    input  CachePkg::cmo_t        req_cmo,          // CMO_NONE, or a CBO's operation
    input  wire [DATA_WIDTH-1:0]  req_wdata,        // write data, an atomic's operand
    input  wire [STRB_WIDTH-1:0]  req_wstrb,
    output logic                  rsp_valid,        // the answer to a read or an atomic
    output logic [DATA_WIDTH-1:0] rsp_data,
    // The request network's local input, the answer network's local output
    output req_link_fwd_t         noc_req_fwd,      // flits to the router
    // A credit's vc is not read: one VC.
    /* verilator lint_off UNUSEDSIGNAL */
    input  link_bwd_t             noc_req_bwd,      // credits from it
    /* verilator lint_on UNUSEDSIGNAL */
    input  rsp_link_fwd_t         noc_rsp_fwd,      // answers from the router
    output link_bwd_t             noc_rsp_bwd       // credits to it
);
    localparam CREDIT_WIDTH = $clog2(BUF_DEPTH + 1);
    localparam logic [SIZE_WIDTH-1:0] SIZE_WORD = SIZE_WIDTH'($clog2(STRB_WIDTH));

    `DC_STATIC_ASSERT(a_buf_depth, BUF_DEPTH >= 1)

    logic [CREDIT_WIDTH-1:0] credits_q;     // free slots of the router's buffer
    logic                    body_q;        // the head went, the body is next
    req_op_e                 op;
    logic                    has_body;
    logic                    send;          // a flit goes out
    rsp_t                    rsp;
    rsp_rest_t               answer;

    // The opcode of a request.
    function automatic req_op_e op_of(logic we, AtomicPkg::atop_t atop, CachePkg::cmo_t cmo);
        if (cmo != CachePkg::CMO_NONE)
            return REQ_CBO;
        else if (atop != AtomicPkg::ATOP_NONE)
            return REQ_ATOMIC;
        else if (we)
            return REQ_WRITE;
        else
            return REQ_READ;
    endfunction

    // The head flit: the route to the shared memory, then where the answer goes.
    function automatic req_flit_t head_of(req_op_e o, logic tail, logic [SIZE_WIDTH-1:0] size,
                                          logic [ADDR_WIDTH-1:0] addr, CachePkg::cmo_t cmo);
        req_rest_t r;
        req_head_t h;
        req_flit_t f;

        r.op     = o;
        r.src_x  = MY_X;
        r.src_y  = MY_Y;
        r.size   = size;
        r.addr   = addr;
        r.cmo    = cmo;
        h.dest_x = MEM_X;
        h.dest_y = MEM_Y;
        h.rest   = r;
        f.head   = 1'b1;
        f.tail   = tail;
        f.vc     = '0;
        f.data   = h;
        return f;
    endfunction

    // The body flit of a WRITE (its data and strobes) or an ATOMIC (its operand and atop).
    function automatic req_flit_t body_of(req_op_e o, logic [DATA_WIDTH-1:0] wdata,
                                          logic [STRB_WIDTH-1:0] wstrb, AtomicPkg::atop_t atop);
        req_write_t  w;
        req_atomic_t a;
        req_flit_t   f;

        w.zero    = '0;
        w.data    = wdata;
        w.strb    = wstrb;
        a.zero    = '0;
        a.operand = wdata;
        a.atop    = atop;
        f.head    = 1'b0;
        f.tail    = 1'b1;
        f.vc      = '0;
        if (o == REQ_ATOMIC)
            f.data = a;
        else
            f.data = w;
        return f;
    endfunction

    assign op       = op_of(req_we, req_atop, req_cmo);
    assign has_body = req_has_body(op);

    // Requests: a flit a clock while the router has room; taken with the last flit.
    assign send              = req_valid && credits_q != '0;
    assign req_ready         = send && (body_q || !has_body);
    assign noc_req_fwd.valid = send;
    assign noc_req_fwd.flit  = body_q ? body_of(op, req_wdata, req_wstrb, req_atop)
                                      : head_of(op, !has_body, req_size, req_addr, req_cmo);

    always_ff @(posedge clk)
        if (!rst_n) begin
            credits_q <= CREDIT_WIDTH'(BUF_DEPTH);
            body_q    <= 1'b0;
        end else begin
            credits_q <= credits_q - CREDIT_WIDTH'(send) + CREDIT_WIDTH'(noc_req_bwd.valid);
            if (send)
                body_q <= has_body && !body_q;
        end

    // Answers: straight to the requester, the credit straight back.
    assign rsp               = noc_rsp_fwd.flit.data;
    assign answer            = rsp.rest;
    assign rsp_valid         = noc_rsp_fwd.valid;
    assign rsp_data          = answer.data;
    assign noc_rsp_bwd.valid = noc_rsp_fwd.valid;
    assign noc_rsp_bwd.vc    = '0;

    // Shared memory is uncached: only accesses of a word or less come (Mig6Pe picks the word).
    `DC_ASSERT(a_word_at_most, !(req_valid && req_size > SIZE_WORD))
    // An offer stays the same until taken (the body is sent from it a clock after the head).
    `DC_ASSERT_NEXT(a_offer_kept, send && !req_ready,
                    req_valid && $stable({req_we, req_addr, req_size, req_atop, req_cmo,
                                          req_wdata}) && (op != REQ_WRITE || $stable(req_wstrb)))
    // The router returns no more credits than it has slots.
    `DC_ASSERT(a_credits_at_most_depth,
               !(noc_req_bwd.valid && !send && credits_q == CREDIT_WIDTH'(BUF_DEPTH)))
    // An answer is one DATA flit to this node.
    `DC_ASSERT(a_answer_one_flit, !(noc_rsp_fwd.valid
                                    && !(noc_rsp_fwd.flit.head && noc_rsp_fwd.flit.tail)))
    `DC_ASSERT(a_answer_is_data, !(noc_rsp_fwd.valid && answer.op != RSP_DATA))
    `DC_ASSERT(a_answer_is_mine, !(noc_rsp_fwd.valid && (rsp.dest_x != MY_X
                                                         || rsp.dest_y != MY_Y)))

endmodule

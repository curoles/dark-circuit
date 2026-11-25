/* Test of NocVirtChIn.
 *
 * Random packets of 1 to 4 flits come in as fast as the sender's credits allow (a credit
 * returns when a flit is popped); a VC allocator grants a waiting packet a random output VC
 * after 0 or more clocks (ROUTE_EARLY: also a head at the front of an idle VC, in that clock);
 * a switch allocator pops the front flit of an active VC in most clocks. ALLOC_COMBINED: the
 * switch allocator gives the VC, so a grant comes with the head's pop (and a one-flit packet
 * is done in that clock). The route of a head flit is the low bits of its data (as an input
 * unit would compute it). A model keeps the flits in the buffer and the state, route and
 * output VC of the packet; every clock the front flit and the state must be the model's,
 * while the packet is active out_flit the front flit with its output VC in the vc field
 * (combined, as a head is granted: with the grant's VC), and the requests the model's:
 * va_req while waiting for a VC, with the route; sa_req while active with a flit, with the
 * route and the output VC (combined: va_req never, sa_req with need_vc instead of va_req).
 * Every case must happen: packets of one flit and of more, a grant in the first clock of
 * waiting and a later one, a full buffer, (BUF_DEPTH > 1) a push and a pop in one clock and a
 * tail popped with the next head behind it, and (combined) a one-flit packet granted and sent
 * in one clock. BUF_DEPTH 3 (FifoT rounds it up to 4) and 1, each with ROUTE_REGISTERED and
 * ROUTE_EARLY (where the first-clock grant is the one at the front), with ALLOC_SEPARATE;
 * ALLOC_COMBINED with BUF_DEPTH 3 and both ROUTEs, and BUF_DEPTH 1 with ROUTE_EARLY; Verilator
 * 20000 clocks, Icarus 2000. Stops at the first mismatch with $fatal.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "../block/noc/dark_circuit_noc.svh"

module TbNocVirtChInCheck #(
    parameter VC_WIDTH   = 2,
    parameter DATA_WIDTH = 16,
    parameter BUF_DEPTH  = 3,
    parameter ROUTE      = NocPkg::ROUTE_REGISTERED,
    parameter ALLOC      = NocPkg::ALLOC_SEPARATE
)(
    input  wire  clk,
    output logic done
);
    localparam PORT_WIDTH = 3;
    localparam EARLY      = ROUTE == NocPkg::ROUTE_EARLY;
    localparam COMBINED   = ALLOC == NocPkg::ALLOC_COMBINED;
    localparam NAME       = BUF_DEPTH + 10 * ROUTE + 100 * ALLOC;   // in messages
`ifdef VERILATOR
    localparam N_CLOCKS   = 20000;
`else
    localparam N_CLOCKS   = 2000;
`endif

    typedef `DC_NOC_FLIT_T(VC_WIDTH, DATA_WIDTH)            flit_t;
    typedef `DC_NOC_FLIT_VLD_T(VC_WIDTH, DATA_WIDTH)        flit_vld_t;
    typedef `DC_NOC_VC_VLD_T(VC_WIDTH)                      vc_vld_t;
    typedef `DC_NOC_VC_IN_STATE_T(PORT_WIDTH, VC_WIDTH)     state_t;
    typedef `DC_NOC_VA_REQ_T(PORT_WIDTH)                    va_req_t;
    typedef `DC_NOC_SA_REQ_T(PORT_WIDTH, VC_WIDTH)          sa_req_t;

    logic                  rst_n;
    flit_vld_t             push;
    logic                  pop;
    flit_vld_t             front;
    flit_t                 out_flit;
    logic [PORT_WIDTH-1:0] front_route;
    vc_vld_t               grant;
    state_t                state;
    va_req_t               va_req;
    sa_req_t               sa_req;

    NocVirtChIn #(.VC_WIDTH(VC_WIDTH), .DATA_WIDTH(DATA_WIDTH), .BUF_DEPTH(BUF_DEPTH),
                  .PORT_WIDTH(PORT_WIDTH), .ROUTE(ROUTE), .ALLOC(ALLOC)) u_virt_ch_in(
        .clk, .rst_n, .push, .pop, .front, .out_flit, .front_route, .grant, .state, .va_req,
        .sa_req);

    // Route of a head flit, as an input unit computes it: here the low bits of its data (the
    // rest of the flit is not used).
    /* verilator lint_off UNUSEDSIGNAL */
    function automatic logic [PORT_WIDTH-1:0] route_of(input flit_t f);
        return f.data[PORT_WIDTH-1:0];
    endfunction
    /* verilator lint_on UNUSEDSIGNAL */

    assign front_route = route_of(front.flit);

    // A flit with its vc field set to vc.
    function automatic flit_t with_vc(input flit_t f, input logic [VC_WIDTH-1:0] vc);
        flit_t g;
        g    = f;
        g.vc = vc;
        return g;
    endfunction

    // Model. Queues of plain vectors: Icarus has no queues of structs.
    localparam FLIT_WIDTH = $bits(flit_t);
    logic [FLIT_WIDTH-1:0] buffer [$];      // flits in the VC, oldest first
    logic [FLIT_WIDTH-1:0] to_send [$];     // flits of packets not pushed yet
    integer                credits;         // the sender's credits
    logic [1:0]            m_state;
    logic [PORT_WIDTH-1:0] m_route;
    logic [VC_WIDTH-1:0]   m_out_vc;
    integer                waited;          // clocks the packet has waited for its VC
    integer                seed;

    // Cases seen.
    integer n_pkt_one;          // a packet of one flit sent
    integer n_pkt_long;         // a packet of more flits sent
    integer n_grant_first;      // a grant in the first clock of waiting
    integer n_grant_later;
    integer n_full;             // the buffer holds BUF_DEPTH flits
    integer n_push_pop;         // a push and a pop in one clock
    integer n_back_to_back;     // a tail popped with the next head behind it
    integer n_grant_done;       // (combined) a one-flit packet granted and sent in one clock

    // A head at the front of an idle VC (the model's): only the flit's head bit is read.
    function automatic logic head_at_front();
        /* verilator lint_off UNUSEDSIGNAL */
        flit_t f0;
        /* verilator lint_on UNUSEDSIGNAL */
        if (m_state != NocPkg::VC_IDLE || buffer.size() == 0)
            return 1'b0;
        f0 = buffer[0];
        return f0.head;
    endfunction

    // The model's VA request: waiting for a VC; early also a head at the front.
    function automatic logic va_expected();
        return m_state == NocPkg::VC_WAIT_VC || (EARLY && head_at_front());
    endfunction

    task automatic new_packet;
        integer len;
        flit_t  f;
        len = 1 + {$random(seed)} % 4;
        for (int i = 0; i < len; i++) begin
            f      = '0;
            f.head = (i == 0);
            f.tail = (i == len - 1);
            f.vc   = VC_WIDTH'($random(seed));
            f.data = DATA_WIDTH'($random(seed));
            to_send.push_back(f);
        end
    endtask

    // Inputs of this clock, after the rising edge.
    task automatic drive;
        push  = '0;
        pop   = 1'b0;
        grant = '0;
        if (to_send.size() < 4)
            new_packet();
        if (credits > 0 && {$random(seed)} % 10 < 6) begin
            push.valid = 1'b1;
            push.flit  = to_send[0];
        end
        if (va_expected() && {$random(seed)} % 2 == 0) begin
            grant.valid = 1'b1;
            grant.vc    = VC_WIDTH'($random(seed));
            pop         = COMBINED;     // the switch pops the head it gives a VC
        end
        if (m_state == NocPkg::VC_ACTIVE && buffer.size() > 0 && {$random(seed)} % 10 < 6)
            pop = 1'b1;
    endtask

    // Outputs of this clock: those of the model. A head asks for its VC (va_expected) with the
    // route now (idle) or the stored one.
    task automatic check;
        logic [PORT_WIDTH-1:0] ask_port;
        logic                  active_req;      // active with a flit: asks the switch
        logic                  sa_expected;
        ask_port    = m_state != NocPkg::VC_IDLE ? m_route
                    : buffer.size() > 0          ? route_of(buffer[0]) : '0;
        active_req  = m_state == NocPkg::VC_ACTIVE && buffer.size() > 0;
        sa_expected = active_req || (COMBINED && va_expected());
        if (front.valid !== (buffer.size() > 0) || (front.valid && front.flit !== buffer[0]))
            $fatal(1, "NocVirtChIn %0d: front %b %h, expected %b %h", BUF_DEPTH, front.valid,
                   front.flit, buffer.size() > 0, buffer.size() > 0 ? buffer[0] : '0);
        if (state.state !== m_state || state.has_flit !== (buffer.size() > 0) ||
            (m_state != NocPkg::VC_IDLE && state.route !== m_route) ||
            (m_state == NocPkg::VC_ACTIVE && state.out_vc !== m_out_vc))
            $fatal(1, "NocVirtChIn %0d: state %0d route %0d vc %0d, expected %0d %0d %0d",
                   BUF_DEPTH, state.state, state.route, state.out_vc, m_state, m_route, m_out_vc);
        if (active_req && out_flit !== with_vc(buffer[0], m_out_vc))
            $fatal(1, "NocVirtChIn %0d: out_flit %h, expected %h", NAME, out_flit,
                   with_vc(buffer[0], m_out_vc));
        if (COMBINED && grant.valid && out_flit !== with_vc(buffer[0], grant.vc))
            $fatal(1, "NocVirtChIn %0d: head out_flit %h, expected %h", NAME, out_flit,
                   with_vc(buffer[0], grant.vc));
        if (va_req.valid !== (!COMBINED && va_expected()) ||
            (va_req.valid && va_req.port !== ask_port))
            $fatal(1, "NocVirtChIn %0d: va_req %b %0d, expected %b", NAME, va_req.valid,
                   va_req.port, !COMBINED && va_expected());
        if (sa_req.valid !== sa_expected ||
            (sa_req.valid && active_req && (sa_req.port !== m_route || sa_req.vc !== m_out_vc ||
                                            sa_req.need_vc !== 1'b0)) ||
            (sa_req.valid && !active_req && (sa_req.port !== ask_port || sa_req.need_vc !== 1'b1)))
            $fatal(1, "NocVirtChIn %0d: sa_req %b %0d %0d %b, expected %b", NAME, sa_req.valid,
                   sa_req.port, sa_req.vc, sa_req.need_vc, sa_expected);
        if (buffer.size() == BUF_DEPTH)
            n_full = n_full + 1;
    endtask

    // Model of the rising edge with the inputs of this clock: the state moves with the front
    // flit of this clock, then the pop and the push change the buffer.
    task automatic model_edge;
        // The flit popped: only its head and tail bits are counted.
        /* verilator lint_off UNUSEDSIGNAL */
        flit_t f;
        /* verilator lint_on UNUSEDSIGNAL */
        flit_t f0;          // the front flit of this clock
        f0 = buffer.size() > 0 ? buffer[0] : '0;
        case (m_state)
            NocPkg::VC_IDLE:
                if (buffer.size() > 0 && f0.head) begin
                    m_route = route_of(f0);
                    waited  = 0;
                    if (EARLY && grant.valid) begin     // granted at the front
                        m_state       = (pop && f0.tail) ? NocPkg::VC_IDLE : NocPkg::VC_ACTIVE;
                        m_out_vc      = grant.vc;
                        n_grant_first = n_grant_first + 1;
                        if (pop && f0.tail) n_grant_done = n_grant_done + 1;
                    end else
                        m_state = NocPkg::VC_WAIT_VC;
                end
            NocPkg::VC_WAIT_VC:
                if (grant.valid) begin
                    m_state  = (pop && f0.tail) ? NocPkg::VC_IDLE : NocPkg::VC_ACTIVE;
                    m_out_vc = grant.vc;
                    if (pop && f0.tail) n_grant_done = n_grant_done + 1;
                    if (waited == 0) n_grant_first = n_grant_first + 1;
                    else             n_grant_later = n_grant_later + 1;
                end else
                    waited = waited + 1;
            default:
                if (pop && f0.tail)
                    m_state = NocPkg::VC_IDLE;
        endcase
        if (pop) begin
            f = buffer.pop_front();
            credits = credits + 1;
            if (f.tail && f.head)    n_pkt_one      = n_pkt_one + 1;
            if (f.tail && !f.head)   n_pkt_long     = n_pkt_long + 1;
            if (f.tail && buffer.size() > 0) n_back_to_back = n_back_to_back + 1;
            if (push.valid)          n_push_pop     = n_push_pop + 1;
        end
        if (push.valid) begin
            buffer.push_back(to_send.pop_front());
            credits = credits - 1;
        end
    endtask

    initial begin
        done           = 1'b0;
        seed           = BUF_DEPTH * 7 + VC_WIDTH + 100 * ROUTE + 1000 * ALLOC;
        credits        = BUF_DEPTH;
        m_state        = NocPkg::VC_IDLE;
        m_route        = '0;
        m_out_vc       = '0;
        waited         = 0;
        n_pkt_one      = 0;
        n_pkt_long     = 0;
        n_grant_first  = 0;
        n_grant_later  = 0;
        n_full         = 0;
        n_push_pop     = 0;
        n_back_to_back = 0;
        n_grant_done   = 0;
        rst_n          = 1'b0;
        push           = '0;
        pop            = 1'b0;
        grant          = '0;
        @(negedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        for (int k = 0; k < N_CLOCKS; k++) begin
            drive();
            #1;
            check();
            model_edge();
            @(negedge clk);
        end
        // With one slot a push can not meet a pop (the credit comes back with the pop), and no
        // head waits behind a tail.
        if (n_pkt_one == 0 || n_pkt_long == 0 || n_grant_first == 0 || n_grant_later == 0 ||
            n_full == 0 || (BUF_DEPTH > 1 && (n_push_pop == 0 || n_back_to_back == 0)) ||
            (COMBINED && n_grant_done == 0))
            $fatal(1, "NocVirtChIn %0d: cases %0d %0d, grant %0d %0d %0d, %0d %0d %0d", NAME,
                   n_pkt_one, n_pkt_long, n_grant_first, n_grant_later, n_grant_done, n_full,
                   n_push_pop, n_back_to_back);
        done = 1'b1;
    end
endmodule

module TbNocVirtChIn;
    wire clk;
    wire done_3;
    wire done_1;
    wire done_3e;
    wire done_1e;
    wire done_3c;
    wire done_3ec;
    wire done_1ec;

    SimClkGen #(.HALF_PERIOD(5)) u_sim_clk_gen(.clk);

    TbNocVirtChInCheck #(.BUF_DEPTH(3)) u_check_3(.clk, .done(done_3));
    TbNocVirtChInCheck #(.BUF_DEPTH(1), .VC_WIDTH(1)) u_check_1(.clk, .done(done_1));
    TbNocVirtChInCheck #(.BUF_DEPTH(3), .ROUTE(NocPkg::ROUTE_EARLY)) u_check_3e(.clk,
                                                                          .done(done_3e));
    TbNocVirtChInCheck #(.BUF_DEPTH(1), .VC_WIDTH(1), .ROUTE(NocPkg::ROUTE_EARLY)) u_check_1e(
        .clk, .done(done_1e));
    TbNocVirtChInCheck #(.BUF_DEPTH(3), .ALLOC(NocPkg::ALLOC_COMBINED)) u_check_3c(.clk,
                                                                         .done(done_3c));
    TbNocVirtChInCheck #(.BUF_DEPTH(3), .ROUTE(NocPkg::ROUTE_EARLY),
                         .ALLOC(NocPkg::ALLOC_COMBINED)) u_check_3ec(.clk, .done(done_3ec));
    TbNocVirtChInCheck #(.BUF_DEPTH(1), .VC_WIDTH(1), .ROUTE(NocPkg::ROUTE_EARLY),
                         .ALLOC(NocPkg::ALLOC_COMBINED)) u_check_1ec(.clk, .done(done_1ec));

    initial begin
        wait (done_3 && done_1 && done_3e && done_1e && done_3c && done_3ec && done_1ec);
        $display("PASS");
        $finish;
    end
endmodule

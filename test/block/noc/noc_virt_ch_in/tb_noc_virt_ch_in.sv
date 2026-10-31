/* Test of NocVirtChIn.
 *
 * Random packets of 1 to 4 flits come in as fast as the sender's credits allow (a credit
 * returns when a flit is popped); a VC allocator grants a waiting packet a random output VC
 * after 0 or more clocks; a switch allocator pops the front flit of an active VC in most
 * clocks. The route of a head flit is the low bits of its data (as an input unit would compute
 * it). A model keeps the flits in the buffer and the state, route and output VC of the packet;
 * every clock the front flit and the state must be the model's. Every case must happen: packets
 * of one flit and of more, a grant in the first clock of waiting and a later one, a full
 * buffer, and (BUF_DEPTH > 1) a push and a pop in one clock and a tail popped with the next
 * head behind it. BUF_DEPTH 3 (FifoT rounds it up to 4) and 1; Verilator 20000 clocks, Icarus 2000.
 * Stops at the first mismatch with $fatal.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "../block/noc/dark_circuit_noc.svh"

module TbNocVirtChInCheck #(
    parameter VC_WIDTH   = 2,
    parameter DATA_WIDTH = 16,
    parameter BUF_DEPTH  = 3
)(
    input  wire  clk,
    output logic done
);
    localparam PORT_WIDTH = 3;
`ifdef VERILATOR
    localparam N_CLOCKS   = 20000;
`else
    localparam N_CLOCKS   = 2000;
`endif

    typedef `DC_NOC_FLIT_T(VC_WIDTH, DATA_WIDTH)            flit_t;
    typedef `DC_NOC_FLIT_VLD_T(VC_WIDTH, DATA_WIDTH)        flit_vld_t;
    typedef `DC_NOC_VC_VLD_T(VC_WIDTH)                      vc_vld_t;
    typedef `DC_NOC_VC_IN_STATE_T(PORT_WIDTH, VC_WIDTH)     state_t;

    logic                  rst_n;
    flit_vld_t             push;
    logic                  pop;
    flit_vld_t             front;
    logic [PORT_WIDTH-1:0] front_route;
    vc_vld_t               grant;
    state_t                state;

    NocVirtChIn #(.VC_WIDTH(VC_WIDTH), .DATA_WIDTH(DATA_WIDTH), .BUF_DEPTH(BUF_DEPTH),
                  .PORT_WIDTH(PORT_WIDTH)) u_virt_ch_in(
        .clk, .rst_n, .push, .pop, .front, .front_route, .grant, .state);

    // Route of a head flit, as an input unit computes it: here the low bits of its data (the
    // rest of the flit is not used).
    /* verilator lint_off UNUSEDSIGNAL */
    function automatic logic [PORT_WIDTH-1:0] route_of(input flit_t f);
        return f.data[PORT_WIDTH-1:0];
    endfunction
    /* verilator lint_on UNUSEDSIGNAL */

    assign front_route = route_of(front.flit);

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
        if (m_state == NocPkg::VC_WAIT_VC && {$random(seed)} % 2 == 0) begin
            grant.valid = 1'b1;
            grant.vc    = VC_WIDTH'($random(seed));
        end
        if (m_state == NocPkg::VC_ACTIVE && buffer.size() > 0 && {$random(seed)} % 10 < 6)
            pop = 1'b1;
    endtask

    // Outputs of this clock: those of the model.
    task automatic check;
        if (front.valid !== (buffer.size() > 0) || (front.valid && front.flit !== buffer[0]))
            $fatal(1, "NocVirtChIn %0d: front %b %h, expected %b %h", BUF_DEPTH, front.valid,
                   front.flit, buffer.size() > 0, buffer.size() > 0 ? buffer[0] : '0);
        if (state.state !== m_state ||
            (m_state != NocPkg::VC_IDLE && state.route !== m_route) ||
            (m_state == NocPkg::VC_ACTIVE && state.out_vc !== m_out_vc))
            $fatal(1, "NocVirtChIn %0d: state %0d route %0d vc %0d, expected %0d %0d %0d",
                   BUF_DEPTH, state.state, state.route, state.out_vc, m_state, m_route, m_out_vc);
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
                    m_state = NocPkg::VC_WAIT_VC;
                    m_route = route_of(f0);
                    waited  = 0;
                end
            NocPkg::VC_WAIT_VC:
                if (grant.valid) begin
                    m_state  = NocPkg::VC_ACTIVE;
                    m_out_vc = grant.vc;
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
        seed           = BUF_DEPTH * 7 + VC_WIDTH;
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
            n_full == 0 || (BUF_DEPTH > 1 && (n_push_pop == 0 || n_back_to_back == 0)))
            $fatal(1, "NocVirtChIn %0d: cases: one %0d long %0d grant %0d %0d full %0d push+pop %0d b2b %0d",
                   BUF_DEPTH, n_pkt_one, n_pkt_long, n_grant_first, n_grant_later, n_full,
                   n_push_pop, n_back_to_back);
        done = 1'b1;
    end
endmodule

module TbNocVirtChIn;
    wire clk;
    wire done_3;
    wire done_1;

    SimClkGen #(.HALF_PERIOD(5)) u_sim_clk_gen(.clk);

    TbNocVirtChInCheck #(.BUF_DEPTH(3)) u_check_3(.clk, .done(done_3));
    TbNocVirtChInCheck #(.BUF_DEPTH(1), .VC_WIDTH(1)) u_check_1(.clk, .done(done_1));

    initial begin
        wait (done_3 && done_1);
        $display("PASS");
        $finish;
    end
endmodule

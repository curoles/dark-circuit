/* NoC virtual channel, the input end: one VC of an input port, behavioral.
 *
 * A buffer of flits (FifoT; BUF_DEPTH flits at most: the sender's credits start there, so a
 * flit never comes while it is full) and the state of the packet at its front. A packet holds
 * the VC from its head flit to its tail flit:
 *   VC_IDLE    -> VC_WAIT_VC  a head flit is at the front: its route (front_route) is kept
 *   VC_IDLE    -> VC_ACTIVE   ... and (ROUTE_EARLY) VC allocation grants it in that clock
 *   VC_WAIT_VC -> VC_ACTIVE   VC allocation grants the packet an output VC (grant): kept
 *   VC_ACTIVE  -> VC_IDLE     switch allocation sends the tail flit (pop)
 * ROUTE says when the head asks VC allocation: ROUTE_REGISTERED in VC_WAIT_VC, the clock after
 * it reached the front, with the stored route (a head leaves the router 3 clocks after it
 * came); ROUTE_EARLY already in VC_IDLE, in the clock it reaches the front, with the route
 * computed then (front_route, combinational: the route logic before VC allocation's arbiter in
 * one clock), and on in VC_WAIT_VC with the stored one when not granted at once (2 clocks).
 * The route comes from outside (the input unit computes it from the head's destination), so
 * the block knows nothing about the topology: a network interface can use it too. A flit
 * popped frees a slot: the input unit returns a credit for this VC upstream. out_flit is the
 * front flit as it leaves: its vc field the packet's output VC (made here, so that a variant
 * that grants and sends in one clock can bypass the grant to it). va_req and sa_req are what
 * the VC asks of the allocators, made here from its state: VC_WAIT_VC asks an output VC of its
 * route; VC_ACTIVE with a flit asks the switch, to its route on its output VC (switch
 * allocation checks the credit). Their fields are kept whether valid or not.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "dark_circuit_assert.svh"
`include "../block/noc/dark_circuit_noc.svh"

module NocVirtChIn #(
    parameter  VC_WIDTH   = 1,
    parameter  DATA_WIDTH = 32,
    parameter  BUF_DEPTH  = 4,                  // flits; the sender's credits start here
    parameter  PORT_WIDTH = 3,                  // bits of an output port number
    parameter  ROUTE      = NocPkg::ROUTE_REGISTERED,   // when a head asks VC allocation
    localparam type FLIT_T     = `DC_NOC_FLIT_T(VC_WIDTH, DATA_WIDTH),
    localparam type FLIT_VLD_T = `DC_NOC_FLIT_VLD_T(VC_WIDTH, DATA_WIDTH),
    localparam type VC_VLD_T   = `DC_NOC_VC_VLD_T(VC_WIDTH),
    localparam type STATE_T    = `DC_NOC_VC_IN_STATE_T(PORT_WIDTH, VC_WIDTH),
    localparam type VA_REQ_T   = `DC_NOC_VA_REQ_T(PORT_WIDTH),
    localparam type SA_REQ_T   = `DC_NOC_SA_REQ_T(PORT_WIDTH, VC_WIDTH)
)(
    input  wire                  clk,
    input  wire                  rst_n,         // synchronous reset, active low
    input  FLIT_VLD_T            push,          // a flit of this VC comes in on the link
    input  wire                  pop,           // switch allocation sends the front flit
    output FLIT_VLD_T            front,         // the flit at the front; valid: not empty
    output FLIT_T                out_flit,      // ... as it leaves: vc = the output VC
    input  wire [PORT_WIDTH-1:0] front_route,   // route of the front flit, when it is a head
    input  VC_VLD_T              grant,         // VC allocation: the packet's output VC
    output STATE_T               state,         // state, flit, route, output VC: for allocators
    output VA_REQ_T              va_req,        // to VC allocation: an output VC of the route
    output SA_REQ_T              sa_req         // to switch allocation: send the front flit
);
    // FifoT holds a power of 2 entries, at least 2: BUF_DEPTH rounded up.
    localparam BUF_ADDR_WIDTH = (BUF_DEPTH > 1) ? $clog2(BUF_DEPTH) : 1;

    `DC_STATIC_ASSERT(a_buf_depth, BUF_DEPTH >= 1)
    `DC_STATIC_ASSERT(a_route, ROUTE == NocPkg::ROUTE_REGISTERED || ROUTE == NocPkg::ROUTE_EARLY)

    localparam EARLY = ROUTE == NocPkg::ROUTE_EARLY;

    FLIT_T                    front_flit;
    logic                     empty;
    // Status the credits make unnecessary (full is only checked).
    /* verilator lint_off UNUSEDSIGNAL */
    logic                     full;
    logic [BUF_ADDR_WIDTH:0]  count;
    logic                     almost_full;
    logic                     almost_empty;
    /* verilator lint_on UNUSEDSIGNAL */
    logic [1:0]               state_q;
    logic [PORT_WIDTH-1:0]    route_q;
    logic [VC_WIDTH-1:0]      out_vc_q;

    FifoT #(.T(FLIT_T), .ADDR_WIDTH(BUF_ADDR_WIDTH)) u_buf(
        .clk, .rst_n, .write(push.valid), .data_in(push.flit), .read(pop),
        .data_out(front_flit), .empty, .full, .count, .almost_full, .almost_empty);

    assign front.valid = !empty;
    assign front.flit  = front_flit;

    // The front flit as it leaves, with the packet's output VC.
    always_comb begin
        out_flit    = front_flit;
        out_flit.vc = out_vc_q;
    end

    always_ff @(posedge clk)
        if (!rst_n)
            state_q <= NocPkg::VC_IDLE;
        else
            case (state_q)
                NocPkg::VC_IDLE:
                    if (front.valid && front.flit.head) begin
                        route_q <= front_route;
                        if (EARLY && grant.valid) begin     // granted in this clock
                            state_q  <= NocPkg::VC_ACTIVE;
                            out_vc_q <= grant.vc;
                        end else
                            state_q <= NocPkg::VC_WAIT_VC;
                    end
                NocPkg::VC_WAIT_VC:
                    if (grant.valid) begin
                        state_q  <= NocPkg::VC_ACTIVE;
                        out_vc_q <= grant.vc;
                    end
                default:    // NocPkg::VC_ACTIVE
                    if (pop && front.flit.tail)
                        state_q <= NocPkg::VC_IDLE;
            endcase

    // The requests to the allocators: an early head asks in VC_IDLE too, with its route now.
    // @kb: rtl/lib/block/noc/allocation
    if (EARLY) begin: g_early
        assign va_req.valid = state_q == NocPkg::VC_WAIT_VC ||
                              (state_q == NocPkg::VC_IDLE && !empty && front_flit.head);
        assign va_req.port  = (state_q == NocPkg::VC_IDLE) ? front_route : route_q;
    end else begin: g_registered
        assign va_req.valid = state_q == NocPkg::VC_WAIT_VC;
        assign va_req.port  = route_q;
    end
    assign sa_req.valid = state_q == NocPkg::VC_ACTIVE && !empty;
    assign sa_req.port  = route_q;
    assign sa_req.vc    = out_vc_q;

    assign state.state    = state_q;
    assign state.has_flit = !empty;
    assign state.route    = route_q;
    assign state.out_vc   = out_vc_q;

    // The protocol around the VC: credits keep the buffer from overflowing; a packet starts
    // with a head flit; VC allocation grants only a packet that asks; switch allocation sends
    // only from an active VC that has a flit.
    `DC_ASSERT(a_no_push_when_full, !(push.valid && full))
    `DC_ASSERT(a_idle_front_is_head, !(state_q == NocPkg::VC_IDLE && front.valid &&
                                       !front.flit.head))
    `DC_ASSERT(a_grant_when_asked, !grant.valid || va_req.valid)
    `DC_ASSERT(a_pop_when_active, !pop || (state_q == NocPkg::VC_ACTIVE && front.valid))

    // The requests' timing (what the allocators may rely on): a VA request not granted stays,
    // for the same port; an SA request not popped stays, for the same port and output VC.
    `DC_ASSERT_NEXT(a_va_req_held, va_req.valid && !grant.valid,
                    va_req.valid && $stable(va_req.port))
    `DC_ASSERT_NEXT(a_sa_req_held, sa_req.valid && !pop,
                    sa_req.valid && $stable({sa_req.port, sa_req.vc}))

endmodule

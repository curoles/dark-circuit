/* NoC virtual channel, the input end: one VC of an input port, behavioral.
 *
 * A buffer of flits (FifoT; BUF_DEPTH flits at most: the sender's credits start there, so a
 * flit never comes while it is full) and the state of the packet at its front. A packet holds
 * the VC from its head flit to its tail flit:
 *   VC_IDLE    -> VC_WAIT_VC  a head flit is at the front: its route (front_route) is kept
 *   VC_WAIT_VC -> VC_ACTIVE   VC allocation grants the packet an output VC (grant): kept
 *   VC_ACTIVE  -> VC_IDLE     switch allocation sends the tail flit (pop)
 * The route comes from outside (the input unit computes it from the head's destination), so
 * the block knows nothing about the topology: a network interface can use it too. A flit
 * popped frees a slot: the input unit returns a credit for this VC upstream.
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
    localparam type FLIT_T     = `DC_NOC_FLIT_T(VC_WIDTH, DATA_WIDTH),
    localparam type FLIT_VLD_T = `DC_NOC_FLIT_VLD_T(VC_WIDTH, DATA_WIDTH),
    localparam type VC_VLD_T   = `DC_NOC_VC_VLD_T(VC_WIDTH),
    localparam type STATE_T    = `DC_NOC_VC_IN_STATE_T(PORT_WIDTH, VC_WIDTH)
)(
    input  wire                  clk,
    input  wire                  rst_n,         // synchronous reset, active low
    input  FLIT_VLD_T            push,          // a flit of this VC comes in on the link
    input  wire                  pop,           // switch allocation sends the front flit
    output FLIT_VLD_T            front,         // the flit at the front; valid: not empty
    input  wire [PORT_WIDTH-1:0] front_route,   // route of the front flit, when it is a head
    input  VC_VLD_T              grant,         // VC allocation: the packet's output VC
    output STATE_T               state          // state, flit, route, output VC: for allocators
);
    // FifoT holds a power of 2 entries, at least 2: BUF_DEPTH rounded up.
    localparam BUF_ADDR_WIDTH = (BUF_DEPTH > 1) ? $clog2(BUF_DEPTH) : 1;

    `DC_STATIC_ASSERT(a_buf_depth, BUF_DEPTH >= 1)

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

    always_ff @(posedge clk)
        if (!rst_n)
            state_q <= NocPkg::VC_IDLE;
        else
            case (state_q)
                NocPkg::VC_IDLE:
                    if (front.valid && front.flit.head) begin
                        state_q <= NocPkg::VC_WAIT_VC;
                        route_q <= front_route;
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

    assign state.state    = state_q;
    assign state.has_flit = !empty;
    assign state.route    = route_q;
    assign state.out_vc   = out_vc_q;

    // The protocol around the VC: credits keep the buffer from overflowing; a packet starts
    // with a head flit; VC allocation grants only a waiting packet; switch allocation sends
    // only from an active VC that has a flit.
    `DC_ASSERT(a_no_push_when_full, !(push.valid && full))
    `DC_ASSERT(a_idle_front_is_head, !(state_q == NocPkg::VC_IDLE && front.valid &&
                                       !front.flit.head))
    `DC_ASSERT(a_grant_when_waiting, !grant.valid || state_q == NocPkg::VC_WAIT_VC)
    `DC_ASSERT(a_pop_when_active, !pop || (state_q == NocPkg::VC_ACTIVE && front.valid))

endmodule

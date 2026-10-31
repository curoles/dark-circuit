/* Input unit of the NoC router with virtual channels, behavioral: one input port.
 *
 * The link's flits go into the buffer of their VC (NocVirtChIn, one per VC, chosen by the flit's
 * vc). Each VC's front head flit gets its route (NocRouteXy). The state of every VC goes to the
 * allocators (vc_state); VC allocation answers a waiting VC with its output VC (vc_grant);
 * switch allocation sends the front flit of one VC per clock (pop): it leaves for the crossbar
 * with the output VC of its packet in its vc field (out), and its slot is free: a credit for its
 * VC goes back upstream on the link, a clock later (a flop keeps the switch allocation off the
 * link's backward wires).
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "dark_circuit_assert.svh"
`include "../block/noc/dark_circuit_noc.svh"

module NocVirtChRtrInputUnit #(
    parameter  NUM_VCS    = 2,                  // virtual channels of the link
    parameter  BUF_DEPTH  = 4,                  // flits of each VC's buffer
    parameter  X_WIDTH    = 2,                  // mesh coordinates
    parameter  Y_WIDTH    = 2,
    parameter  DATA_WIDTH = 32,                 // data of a flit
    parameter  MY_X       = 0,                  // where the router is
    parameter  MY_Y       = 0,
    localparam VC_WIDTH   = `DC_NOC_VC_WIDTH(NUM_VCS),
    localparam PORT_WIDTH = `DC_NOC_PORT_WIDTH(NocPkg::MESH_PORTS),
    localparam type FLIT_T     = `DC_NOC_FLIT_T(VC_WIDTH, DATA_WIDTH),
    localparam type HEAD_T     = `DC_NOC_HEAD_T(X_WIDTH, Y_WIDTH, DATA_WIDTH),
    localparam type FLIT_VLD_T = `DC_NOC_FLIT_VLD_T(VC_WIDTH, DATA_WIDTH),
    localparam type VC_VLD_T   = `DC_NOC_VC_VLD_T(VC_WIDTH),
    localparam type LINK_FWD_T = `DC_NOC_LINK_FWD_T(VC_WIDTH, DATA_WIDTH),
    localparam type LINK_BWD_T = `DC_NOC_LINK_BWD_T(VC_WIDTH),
    localparam type VC_STATE_T = `DC_NOC_VC_IN_STATE_T(PORT_WIDTH, VC_WIDTH)
)(
    input  wire                     clk,
    input  wire                     rst_n,      // synchronous reset, active low
    input  LINK_FWD_T               in_fwd,     // the link into the port: flits in
    output LINK_BWD_T               in_bwd,     //   and credits back
    output VC_STATE_T [NUM_VCS-1:0] vc_state,   // every VC: state, flit, route, output VC
    input  VC_VLD_T   [NUM_VCS-1:0] vc_grant,   // VC allocation: a waiting VC's output VC
    input  VC_VLD_T                 pop,        // switch allocation: send VC pop.vc's flit
    output FLIT_VLD_T               out         // that flit, with its output VC, to the crossbar
);
    `DC_STATIC_ASSERT(a_vcs, NUM_VCS >= 1)

    FLIT_VLD_T [NUM_VCS-1:0] front;             // the front flit of each VC
    VC_VLD_T                 credit_q;          // the credit of the flit popped a clock ago

    for (genvar v = 0; v < NUM_VCS; v++) begin: g_vc
        FLIT_VLD_T             push;            // the link's flit, when it is of this VC
        // The front flit read as a head: only its destination is used.
        /* verilator lint_off UNUSEDSIGNAL */
        HEAD_T                 head;
        /* verilator lint_on UNUSEDSIGNAL */
        logic [PORT_WIDTH-1:0] route;

        assign push.valid = in_fwd.valid && in_fwd.flit.vc == VC_WIDTH'(v);
        assign push.flit  = in_fwd.flit;
        assign head       = front[v].flit.data;

        NocRouteXy #(.X_WIDTH(X_WIDTH), .Y_WIDTH(Y_WIDTH), .MY_X(MY_X), .MY_Y(MY_Y)) u_route(
            .dest_x(head.dest_x), .dest_y(head.dest_y), .port(route));

        NocVirtChIn #(.VC_WIDTH(VC_WIDTH), .DATA_WIDTH(DATA_WIDTH), .BUF_DEPTH(BUF_DEPTH),
                      .PORT_WIDTH(PORT_WIDTH)) u_vc(
            .clk, .rst_n, .push, .pop(pop.valid && pop.vc == VC_WIDTH'(v)), .front(front[v]),
            .front_route(route), .grant(vc_grant[v]), .state(vc_state[v]));
    end

    // A flit with its vc field set to vc.
    function automatic FLIT_T with_vc(input FLIT_T f, input logic [VC_WIDTH-1:0] vc);
        FLIT_T g;
        g    = f;
        g.vc = vc;
        return g;
    endfunction

    assign out.valid = pop.valid;
    assign out.flit  = with_vc(front[pop.vc].flit, vc_state[pop.vc].out_vc);

    always_ff @(posedge clk)
        if (!rst_n) credit_q <= '0;
        else        credit_q <= pop;

    assign in_bwd = credit_q;

    // The sender keeps to the link's VCs and switch allocation names one of them: a check only
    // when some vc values name no VC (NUM_VCS not a power of 2); one bit wider for NUM_VCS.
    if (NUM_VCS < (1 << VC_WIDTH)) begin: g_vc_check
        `DC_ASSERT(a_flit_vc_exists, !in_fwd.valid ||
                                     {1'b0, in_fwd.flit.vc} < (VC_WIDTH + 1)'(NUM_VCS))
        `DC_ASSERT(a_pop_vc_exists, !pop.valid || {1'b0, pop.vc} < (VC_WIDTH + 1)'(NUM_VCS))
    end

endmodule

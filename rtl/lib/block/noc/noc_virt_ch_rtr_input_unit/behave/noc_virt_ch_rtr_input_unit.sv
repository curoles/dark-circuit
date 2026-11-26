/* Input unit of the NoC router with virtual channels, behavioral: one input port.
 *
 * The link's flits go into the buffer of their VC (NocVirtChIn, one per VC, chosen by the flit's
 * vc). Each VC's front head flit gets its route (NocRouteXy). The state of every VC goes to the
 * allocators (vc_state), and its requests to them (va_req, sa_req: NocVirtChIn's); VC
 * allocation answers a waiting VC with its output VC (vc_grant);
 * switch allocation sends the front flit of one VC per clock (pop): it leaves for the crossbar
 * with the output VC of its packet in its vc field (out; the VC's out_flit), and its slot is
 * free: a credit for its
 * VC goes back upstream on the link, a clock later (a flop keeps the switch allocation off the
 * link's backward wires).
 *
 *                          +-----------------+   front[v]   +-------------+
 *   in_fwd ---> by vc ---->| NocVirtChIn [v] |-----+------->| pop.vc      |---> out
 *   (link)                 |  [NUM_VCS]      |     |        | picks; vc = |    (crossbar)
 *                          +-----------------+     |        | out_vc      |
 *                            ^       ^      |      v        +-------------+
 *                      route |       | grant|   NocRouteXy [v] (the front head's destination)
 *                            +-------|------|------+
 *                      vc_grant[v] --+      +---> vc_state[v] (to the allocators)
 *
 *   in_bwd <--- flop <--- pop (switch allocation)
 *   (link)
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
    parameter  ROUTE      = NocPkg::ROUTE_REGISTERED,   // when a head asks VC allocation
    parameter  ALLOC      = NocPkg::ALLOC_SEPARATE,     // who gives a head its output VC
    localparam VC_WIDTH   = `DC_NOC_VC_WIDTH(NUM_VCS),
    localparam PORT_WIDTH = `DC_NOC_PORT_WIDTH(NocPkg::MESH_PORTS),
    localparam type FLIT_T     = `DC_NOC_FLIT_T(VC_WIDTH, DATA_WIDTH),
    localparam type HEAD_T     = `DC_NOC_HEAD_T(X_WIDTH, Y_WIDTH, DATA_WIDTH),
    localparam type FLIT_VLD_T = `DC_NOC_FLIT_VLD_T(VC_WIDTH, DATA_WIDTH),
    localparam type VC_VLD_T   = `DC_NOC_VC_VLD_T(VC_WIDTH),
    localparam type LINK_FWD_T = `DC_NOC_LINK_FWD_T(VC_WIDTH, DATA_WIDTH),
    localparam type LINK_BWD_T = `DC_NOC_LINK_BWD_T(VC_WIDTH),
    localparam type VC_STATE_T = `DC_NOC_VC_IN_STATE_T(PORT_WIDTH, VC_WIDTH),
    localparam type VA_REQ_T   = `DC_NOC_VA_REQ_T(PORT_WIDTH),
    localparam type SA_REQ_T   = `DC_NOC_SA_REQ_T(PORT_WIDTH, VC_WIDTH)
)(
    input  wire                     clk,
    input  wire                     rst_n,      // synchronous reset, active low
    input  LINK_FWD_T               in_fwd,     // the link into the port: flits in
    output LINK_BWD_T               in_bwd,     //   and credits back
    output VC_STATE_T [NUM_VCS-1:0] vc_state,   // every VC: state, flit, route, output VC
    output VA_REQ_T   [NUM_VCS-1:0] va_req,     // every VC: its request to VC allocation
    output SA_REQ_T   [NUM_VCS-1:0] sa_req,     // ... to switch allocation
    input  VC_VLD_T   [NUM_VCS-1:0] vc_grant,   // VC allocation: a waiting VC's output VC
    input  VC_VLD_T                 pop,        // switch allocation: send VC pop.vc's flit
    output FLIT_VLD_T               out         // that flit, with its output VC, to the crossbar
);
    `DC_STATIC_ASSERT(a_vcs, NUM_VCS >= 1)

    FLIT_T     [NUM_VCS-1:0] out_flits;         // each VC's front flit as it leaves
    FLIT_T                   pop_flit;          // ... of the VC popped
    VC_VLD_T                 credit_q;          // the credit of the flit popped a clock ago

    for (genvar v = 0; v < NUM_VCS; v++) begin: g_vc
        FLIT_VLD_T             push;            // the link's flit, when it is of this VC
        // Its front flit (a local: Icarus misreads a field of an array's element with one VC):
        // only the head's destination is read (its valid: the state's has_flit).
        /* verilator lint_off UNUSEDSIGNAL */
        FLIT_VLD_T             front_v;
        /* verilator lint_on UNUSEDSIGNAL */
        FLIT_T                 out_flit_v;      // ... as it leaves
        VA_REQ_T               va_req_v;        // its requests (locals, as front_v)
        SA_REQ_T               sa_req_v;
        // The front flit read as a head: only its destination is used.
        /* verilator lint_off UNUSEDSIGNAL */
        HEAD_T                 head;
        /* verilator lint_on UNUSEDSIGNAL */
        logic [PORT_WIDTH-1:0] route;

        assign push.valid = in_fwd.valid && in_fwd.flit.vc == VC_WIDTH'(v);
        assign push.flit  = in_fwd.flit;
        assign out_flits[v] = out_flit_v;
        assign va_req[v]    = va_req_v;
        assign sa_req[v]    = sa_req_v;
        assign head         = front_v.flit.data;

        NocRouteXy #(.X_WIDTH(X_WIDTH), .Y_WIDTH(Y_WIDTH), .MY_X(MY_X), .MY_Y(MY_Y)) u_route(
            .dest_x(head.dest_x), .dest_y(head.dest_y), .port(route));

        NocVirtChIn #(.VC_WIDTH(VC_WIDTH), .DATA_WIDTH(DATA_WIDTH), .BUF_DEPTH(BUF_DEPTH),
                      .PORT_WIDTH(PORT_WIDTH), .ROUTE(ROUTE), .ALLOC(ALLOC)) u_vc(
            .clk, .rst_n, .push, .pop(pop.valid && pop.vc == VC_WIDTH'(v)), .front(front_v),
            .out_flit(out_flit_v),
            .front_route(route), .grant(vc_grant[v]), .state(vc_state[v]), .va_req(va_req_v),
            .sa_req(sa_req_v));
    end

    // The popped VC's flit as it leaves.
    assign pop_flit  = out_flits[pop.vc];
    assign out.valid = pop.valid;
    assign out.flit  = pop_flit;

    always_ff @(posedge clk)
        if (!rst_n) credit_q <= '0;
        else        credit_q <= pop;

    assign in_bwd = credit_q;

    // A popped flit's credit goes back on the link in the clock after, for its VC.
    `DC_ASSERT_NEXT(a_credit_next, pop.valid, in_bwd.valid && in_bwd.vc == $past(pop.vc))

    // The sender keeps to the link's VCs and switch allocation names one of them: a check only
    // when some vc values name no VC (NUM_VCS not a power of 2); one bit wider for NUM_VCS.
    if (NUM_VCS < (1 << VC_WIDTH)) begin: g_vc_check
        `DC_ASSERT(a_flit_vc_exists, !in_fwd.valid ||
                                     {1'b0, in_fwd.flit.vc} < (VC_WIDTH + 1)'(NUM_VCS))
        `DC_ASSERT(a_pop_vc_exists, !pop.valid || {1'b0, pop.vc} < (VC_WIDTH + 1)'(NUM_VCS))
    end

endmodule

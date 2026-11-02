/* Input unit of the NoC router with virtual channels, made of blocks and gates: one input port.
 *
 * Same ports, parameters and behavior as the behave version (see there). The link's vc and
 * switch allocation's pop.vc are decoded (Decoder, enabled by their valid) into a push and a
 * pop per VC. Each VC's front flit gets its output VC in the vc field before the multiplexer,
 * so one MuxN on pop.vc picks the flit that leaves (no multiplexer with one VC).
 *
 *   in_fwd.vc --> Decoder (en: in_fwd.valid) --> push[v] --+  +-----------------+
 *   in_fwd.flit ------------------------------------------+-->| NocVirtChIn [v] |--> vc_state[v]
 *   pop.vc -----> Decoder (en: pop.valid) ----> pop[v] ------>|  [NUM_VCS]      |
 *   vc_grant[v] --------------------------------------------->|                 |
 *                             NocRouteXy [v] --> route ------>|                 |
 *                                   ^ front head's dest       +-----------------+
 *                                   |                            | front[v]  | out_vc
 *                                   +----------------------------+           v
 *                                                       flit with vc = out_vc: cand[v]
 *   pop.vc --> MuxN (cand) --> out.flit;  pop.valid --> out.valid
 *   pop --> DffSyncRst --> in_bwd (the credit, a clock later)
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
    localparam VC_N = 1 << VC_WIDTH;            // outputs of a vc decoder

    `DC_STATIC_ASSERT(a_vcs, NUM_VCS >= 1)

    // The decoders' outputs above NUM_VCS - 1 are never set (the vc names a VC).
    /* verilator lint_off UNUSEDSIGNAL */
    wire [VC_N-1:0]                  push_vc;   // per VC: the link's flit is of it
    wire [VC_N-1:0]                  pop_vc;    // per VC: switch allocation sends its flit
    /* verilator lint_on UNUSEDSIGNAL */
    wire [NUM_VCS-1:0][$bits(FLIT_T)-1:0] cand; // per VC: its front flit with its output VC
    FLIT_T                           out_flit;

    Decoder #(.SIZE(VC_WIDTH)) u_decoder_push(.in(in_fwd.flit.vc), .en(in_fwd.valid),
                                              .out(push_vc));
    Decoder #(.SIZE(VC_WIDTH)) u_decoder_pop(.in(pop.vc), .en(pop.valid), .out(pop_vc));

    for (genvar v = 0; v < NUM_VCS; v++) begin: g_vc
        FLIT_VLD_T             push;            // the link's flit, when it is of this VC
        VC_STATE_T             state;
        // The front flit: its valid is state's has_flit (the allocators read that one) and its
        // vc is replaced; read as a head, only its destination is used.
        /* verilator lint_off UNUSEDSIGNAL */
        FLIT_VLD_T             front;
        HEAD_T                 head;
        /* verilator lint_on UNUSEDSIGNAL */
        logic [PORT_WIDTH-1:0] route;
        FLIT_T                 with_out_vc;     // the front flit as it leaves

        assign push.valid = push_vc[v];
        assign push.flit  = in_fwd.flit;
        assign head       = front.flit.data;

        NocRouteXy #(.X_WIDTH(X_WIDTH), .Y_WIDTH(Y_WIDTH), .MY_X(MY_X), .MY_Y(MY_Y)) u_route(
            .dest_x(head.dest_x), .dest_y(head.dest_y), .port(route));

        NocVirtChIn #(.VC_WIDTH(VC_WIDTH), .DATA_WIDTH(DATA_WIDTH), .BUF_DEPTH(BUF_DEPTH),
                      .PORT_WIDTH(PORT_WIDTH)) u_vc(
            .clk, .rst_n, .push, .pop(pop_vc[v]), .front, .front_route(route),
            .grant(vc_grant[v]), .state);

        assign with_out_vc.head = front.flit.head;
        assign with_out_vc.tail = front.flit.tail;
        assign with_out_vc.vc   = state.out_vc;
        assign with_out_vc.data = front.flit.data;
        assign cand[v]          = with_out_vc;
        assign vc_state[v]      = state;
    end

    if (NUM_VCS == 1) begin: g_one_vc
        assign out_flit = cand[0];
    end else begin: g_mux
        MuxN #(.N(NUM_VCS), .WIDTH($bits(FLIT_T))) u_mux_n_out(
            .in(cand), .sel(pop.vc), .out(out_flit));
    end

    assign out.valid = pop.valid;
    assign out.flit  = out_flit;

    DffSyncRst #($bits(VC_VLD_T)) u_dff_sync_rst_credit(.clk, .rst_n, .in(pop), .out(in_bwd));

    // The sender keeps to the link's VCs and switch allocation names one of them: a check only
    // when some vc values name no VC (NUM_VCS not a power of 2); one bit wider for NUM_VCS.
    if (NUM_VCS < (1 << VC_WIDTH)) begin: g_vc_check
        `DC_ASSERT(a_flit_vc_exists, !in_fwd.valid ||
                                     {1'b0, in_fwd.flit.vc} < (VC_WIDTH + 1)'(NUM_VCS))
        `DC_ASSERT(a_pop_vc_exists, !pop.valid || {1'b0, pop.vc} < (VC_WIDTH + 1)'(NUM_VCS))
    end

endmodule

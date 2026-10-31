/* NoC router of a 2D mesh with virtual channels (skeleton: the input units and the output VC
 * states; VC allocation, switch allocation and the crossbar are placeholders, so no flit moves).
 *
 * N ports, each an input and an output link (dark_circuit_noc.svh). The router is input-queued:
 * flits wait only in the input units (NocVirtChRtrInputUnit: a buffer per VC, the XY route of
 * each head, a credit back for every flit that leaves). The output side keeps no flits, only
 * the state of the next router's input VCs (NocVirtChOut per VC of each output link): a credit
 * count, BUF_DEPTH after reset, and whether a packet holds the VC. It follows the link itself:
 * a flit sent on out_fwd takes a credit (its tail frees the VC), a credit on out_bwd returns
 * one; VC allocation takes a free output VC for a packet's head. Parts to come: VC allocation
 * (waiting input VCs, free output VCs), switch allocation (active input VCs with a flit, output
 * VCs with a credit; one flit per input and per output each clock), the crossbar (NocMuxXbar).
 *
 *              +-----------------------+  xbar_in  +----------+  out_fwd
 *   in_fwd --->| NocVirtChRtrInputUnit |---------->| crossbar |---+-------> next router
 *   in_bwd <---| [N]: VC buffers,      |           +----------+   |
 *   (credits)  | routes, credits back  |                ^ sel     | flits sent
 *              +-----------------------+                |         v
 *                in_vc_state |  ^ vc_grant, pop         |   +--------------+
 *                            v  |                       |   | NocVirtChOut |<--- out_bwd
 *              +----------------------------------------+   | [N][NUM_VCS] |    (credits)
 *              | VC allocation, switch allocation       |<--| credits, free|
 *              | (to come)                              |-->|              |
 *              +----------------------------------------+   +--------------+
 *              (allocation reads out_vc_state and drives vc_alloc)
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "dark_circuit_assert.svh"
`include "../block/noc/dark_circuit_noc.svh"

module NocVirtChRouter #(
    parameter  N          = NocPkg::MESH_PORTS, // ports: inputs and outputs
    parameter  NUM_VCS    = 2,                  // virtual channels on every link
    parameter  BUF_DEPTH  = 4,                  // flits of an input buffer per VC
    parameter  X_WIDTH    = 2,                  // mesh coordinates
    parameter  Y_WIDTH    = 2,
    parameter  DATA_WIDTH = 32,                 // data of a flit
    parameter  MY_X       = 0,                  // where this router is
    parameter  MY_Y       = 0,
    localparam VC_WIDTH   = `DC_NOC_VC_WIDTH(NUM_VCS),
    localparam PORT_WIDTH = `DC_NOC_PORT_WIDTH(N),
    localparam type FLIT_VLD_T = `DC_NOC_FLIT_VLD_T(VC_WIDTH, DATA_WIDTH),
    localparam type VC_VLD_T   = `DC_NOC_VC_VLD_T(VC_WIDTH),
    localparam type VC_STATE_T = `DC_NOC_VC_IN_STATE_T(PORT_WIDTH, VC_WIDTH),
    localparam type LINK_FWD_T = `DC_NOC_LINK_FWD_T(VC_WIDTH, DATA_WIDTH),
    localparam type LINK_BWD_T = `DC_NOC_LINK_BWD_T(VC_WIDTH)
)(
    input  wire               clk,
    input  wire               rst_n,        // synchronous reset, active low
    input  LINK_FWD_T [N-1:0] in_fwd,       // links into the router: flits in
    output LINK_BWD_T [N-1:0] in_bwd,       //   and their credits back
    output LINK_FWD_T [N-1:0] out_fwd,      // links out of the router
    input  LINK_BWD_T [N-1:0] out_bwd
);
    `DC_STATIC_ASSERT(a_mesh_ports, N == NocPkg::MESH_PORTS)

    // Input side: per input port, the state of its VCs, the grants of VC allocation, the pop of
    // switch allocation and the flit it sends to the crossbar.
    // The allocators and the crossbar, to come, read the states and the flits.
    /* verilator lint_off UNUSEDSIGNAL */
    VC_STATE_T [N-1:0][NUM_VCS-1:0] in_vc_state;
    FLIT_VLD_T [N-1:0]              xbar_in;
    /* verilator lint_on UNUSEDSIGNAL */
    VC_VLD_T   [N-1:0][NUM_VCS-1:0] vc_grant;
    VC_VLD_T   [N-1:0]              pop;

    for (genvar p = 0; p < N; p++) begin: g_in
        NocVirtChRtrInputUnit #(.NUM_VCS(NUM_VCS), .BUF_DEPTH(BUF_DEPTH), .X_WIDTH(X_WIDTH),
                                .Y_WIDTH(Y_WIDTH), .DATA_WIDTH(DATA_WIDTH), .MY_X(MY_X),
                                .MY_Y(MY_Y)) u_input(
            .clk, .rst_n, .in_fwd(in_fwd[p]), .in_bwd(in_bwd[p]), .vc_state(in_vc_state[p]),
            .vc_grant(vc_grant[p]), .pop(pop[p]), .out(xbar_in[p]));
    end

    // Output side: per output port, the state of the next router's input VCs, following the
    // link: a flit sent on a VC, its tail, a credit back for it; VC allocation takes one.
    //   out_fwd[p] (flit on VC v, its tail) ---> NocVirtChOut [p][v] ---> out_vc_state[p][v]
    //   out_bwd[p] (credit for VC v) -----------^     ^                   (free, has_credit)
    //   vc_alloc[p][v] (VC allocation) ---------------+
    // VC and switch allocation, to come, read the states.
    /* verilator lint_off UNUSEDSIGNAL */
    NocPkg::vc_out_state_t [N-1:0][NUM_VCS-1:0] out_vc_state;
    /* verilator lint_on UNUSEDSIGNAL */
    logic                  [N-1:0][NUM_VCS-1:0] vc_alloc;

    for (genvar p = 0; p < N; p++) begin: g_out
        for (genvar v = 0; v < NUM_VCS; v++) begin: g_vc
            logic send;         // a flit goes out on this VC

            assign send = out_fwd[p].valid && out_fwd[p].flit.vc == VC_WIDTH'(v);

            NocVirtChOut #(.BUF_DEPTH(BUF_DEPTH)) u_out_vc(
                .clk, .rst_n, .alloc(vc_alloc[p][v]), .send,
                .send_tail(send && out_fwd[p].flit.tail),
                .credit(out_bwd[p].valid && out_bwd[p].vc == VC_WIDTH'(v)),
                .state(out_vc_state[p][v]));
        end
    end

    // Placeholders until the allocators and the crossbar: nothing is granted, taken or sent.
    assign vc_grant = '0;
    assign pop      = '0;
    assign vc_alloc = '0;
    assign out_fwd  = '0;

endmodule

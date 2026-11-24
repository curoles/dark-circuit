/* NoC router of a 2D mesh with virtual channels, made of the NoC blocks (behave or struct,
 * whichever versions the flist has).
 *
 * N ports, each an input and an output link (dark_circuit_noc.svh). The router is input-queued:
 * flits wait only in the input units (NocVirtChRtrInputUnit: a buffer per VC, the XY route of
 * each head, a credit back for every flit that leaves). The output side keeps no flits, only
 * the state of the next router's input VCs (NocVirtChRtrOutputUnit per output link: a
 * NocVirtChOut per VC): a credit count, BUF_DEPTH after reset, and whether a packet holds the
 * VC. It follows the link itself:
 * a flit sent on out_fwd takes a credit (its tail frees the VC), a credit on out_bwd returns
 * one. Allocation (NocVirtChRtrAlloc) serves the input VCs' requests: VC allocation
 * (NocVirtChAlloc) gives a waiting head a free output VC of its route's port; switch allocation
 * (NocSwitchAlloc) lets active input VCs with a flit and a credit send, one flit per input and
 * per output each clock; the popped flits cross the crossbar (NocMuxXbar) to out_fwd in the
 * same clock.
 *
 * The router has no logic of its own, only its parts and the wiring between them, so this one
 * file serves both flists. A variant of its timing lives in its parts, not here: an input VC
 * that asks the allocators sooner (its requests, NocVirtChIn), an allocation that couples VC
 * and switch allocation (NocVirtChRtrAlloc); the allocators serve requests and know nothing of
 * the input VCs' states (kb rtl/lib/block/noc/allocation).
 *
 * The pipeline of a head flit, measured (TbNocVirtChRouter, a lone packet), and the textbook's
 * stages: a head leaves 3 clocks after it came; a body or tail flit 1 clock after the flit before
 * it, as it has no route or VC to get (it goes with its head's).
 *   clock 0   BW      on in_fwd; written into its VC's buffer at the edge
 *   clock 1   RC      at the front: NocRouteXy gives its route; the VC waits for an output VC
 *   clock 2   VA      NocVirtChAlloc gives it an output VC; the VC is active
 *   clock 3   SA, ST  NocSwitchAlloc pops it; the crossbar puts it on out_fwd
 *   +DELAY    LT      NocLinkWire to the next router
 *
 *              +-----------------------+  xbar_in  +----------+  out_fwd
 *   in_fwd --->| NocVirtChRtrInputUnit |---------->| crossbar |---+-------> next router
 *   in_bwd <---| [N]: VC buffers,      |           +----------+   |
 *   (credits)  | routes, credits back  |                ^ sel     | flits sent
 *              +-----------------------+                |         v
 *         va_req, sa_req |  ^ vc_grant, pop         |   +--------------+
 *                            v  |                       |   | NocVirtChRtr |<--- out_bwd
 *              +----------------------------------------+   | OutputUnit   |    (credits)
 *              | NocVirtChRtrAlloc: NocVirtChAlloc (VC  |<--| [N]: credits,|
 *              | allocation), NocSwitchAlloc (switch)   |-->| free per VC  |
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
    parameter  ROUTE      = NocPkg::ROUTE_REGISTERED,   // when a head asks VC allocation
    localparam VC_WIDTH   = `DC_NOC_VC_WIDTH(NUM_VCS),
    localparam PORT_WIDTH = `DC_NOC_PORT_WIDTH(N),
    localparam type FLIT_T     = `DC_NOC_FLIT_T(VC_WIDTH, DATA_WIDTH),
    localparam type FLIT_VLD_T = `DC_NOC_FLIT_VLD_T(VC_WIDTH, DATA_WIDTH),
    localparam type VC_VLD_T   = `DC_NOC_VC_VLD_T(VC_WIDTH),
    localparam type VC_STATE_T = `DC_NOC_VC_IN_STATE_T(PORT_WIDTH, VC_WIDTH),
    localparam type VA_REQ_T   = `DC_NOC_VA_REQ_T(PORT_WIDTH),
    localparam type SA_REQ_T   = `DC_NOC_SA_REQ_T(PORT_WIDTH, VC_WIDTH),
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

    // Input side: per input port, its VCs' requests to the allocators, the grants of VC
    // allocation, the pop of switch allocation and the flit it sends to the crossbar.
    VA_REQ_T   [N-1:0][NUM_VCS-1:0] in_va_req;
    SA_REQ_T   [N-1:0][NUM_VCS-1:0] in_sa_req;
    // The VCs' states: for the input units' users that watch them; allocation reads requests.
    /* verilator lint_off UNUSEDSIGNAL */
    VC_STATE_T [N-1:0][NUM_VCS-1:0] in_vc_state;
    /* verilator lint_on UNUSEDSIGNAL */
    FLIT_VLD_T [N-1:0]              xbar_in;
    VC_VLD_T   [N-1:0][NUM_VCS-1:0] vc_grant;
    VC_VLD_T   [N-1:0]              pop;

    for (genvar p = 0; p < N; p++) begin: g_in
        NocVirtChRtrInputUnit #(.NUM_VCS(NUM_VCS), .BUF_DEPTH(BUF_DEPTH), .X_WIDTH(X_WIDTH),
                                .Y_WIDTH(Y_WIDTH), .DATA_WIDTH(DATA_WIDTH), .MY_X(MY_X),
                                .MY_Y(MY_Y), .ROUTE(ROUTE)) u_input(
            .clk, .rst_n, .in_fwd(in_fwd[p]), .in_bwd(in_bwd[p]), .vc_state(in_vc_state[p]),
            .va_req(in_va_req[p]), .sa_req(in_sa_req[p]),
            .vc_grant(vc_grant[p]), .pop(pop[p]), .out(xbar_in[p]));
    end

    // Output side: per output port, the state of the next router's input VCs, following the
    // link (the flits sent on out_fwd, the credits back on out_bwd); VC allocation takes one.
    NocPkg::vc_out_state_t [N-1:0][NUM_VCS-1:0] out_vc_state;
    logic                  [N-1:0][NUM_VCS-1:0] vc_alloc;

    for (genvar p = 0; p < N; p++) begin: g_out
        NocVirtChRtrOutputUnit #(.NUM_VCS(NUM_VCS), .BUF_DEPTH(BUF_DEPTH),
                                 .DATA_WIDTH(DATA_WIDTH)) u_output(
            .clk, .rst_n, .out_fwd(out_fwd[p]), .out_bwd(out_bwd[p]),
            .vc_alloc(vc_alloc[p]), .vc_state(out_vc_state[p]));
    end

    // Allocation: VC allocation (a waiting head gets a free output VC of its route's port) and
    // switch allocation (the flits that cross the crossbar this clock).
    logic  [N-1:0][PORT_WIDTH-1:0] xbar_sel;
    logic  [N-1:0]                 xbar_valid;

    NocVirtChRtrAlloc #(.N(N), .NUM_VCS(NUM_VCS)) u_alloc(
        .clk, .rst_n, .va_req(in_va_req), .sa_req(in_sa_req), .out_vc_state, .vc_grant,
        .vc_alloc, .pop, .xbar_sel, .xbar_valid);

    // The crossbar: the popped flits go to their outputs.
    //   pop[p] ---> input unit p ---> xbar_in[p].flit ---> NocMuxXbar ---> out_fwd[r].flit
    //   xbar_sel[r] (the input of output r) ------------------^        xbar_valid[r] -> .valid
    FLIT_T [N-1:0]                 xbar_flit;   // the flits into the crossbar
    FLIT_T [N-1:0]                 xbar_out;    // its outputs

    for (genvar p = 0; p < N; p++) begin: g_xbar_in
        assign xbar_flit[p] = xbar_in[p].flit;

        // The input unit sends a flit exactly when it is popped.
        `DC_ASSERT(a_sends_when_popped, xbar_in[p].valid == pop[p].valid)
    end

    NocMuxXbar #(.N(N), .WIDTH($bits(FLIT_T))) u_xbar(.in(xbar_flit), .sel(xbar_sel),
                                                     .out(xbar_out));

    for (genvar r = 0; r < N; r++) begin: g_out_fwd
        assign out_fwd[r].valid = xbar_valid[r];
        assign out_fwd[r].flit  = xbar_out[r];
    end

endmodule

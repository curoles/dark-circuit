/* NoC router of a 2D mesh with virtual channels (sketch: ports, types and the route of a head
 * flit; the other parts are placeholders).
 *
 * N ports, each an input and an output link. A link carries flits (dark_circuit_noc.svh:
 * multi-flit packets, head and tail flags, a vc) and goes back with credits. The vc of a flit
 * is its virtual channel on this link: each router writes the output VC it allocated into the
 * flits it sends. Each input has a buffer of BUF_DEPTH flits per VC; when a flit leaves it,
 * a credit for that VC goes back upstream (credit_valid, credit_vc: one flit leaves an input
 * per clock, so one credit at most). A sender keeps a credit count per VC of the link, BUF_DEPTH
 * after reset, and sends a flit only while its VC's count is above 0 (no ready). The router at
 * (MY_X, MY_Y) routes XY: a head flit goes east or west until its dest_x is reached, then north
 * or south, then out of the local port; the body and tail flits follow their head. Parts to
 * come: the input buffers per VC, VC allocation, switch allocation, the crossbar (NocMuxXbar),
 * the credit counts of the outputs.
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
    localparam FLIT_WIDTH = `DC_NOC_FLIT_WIDTH(VC_WIDTH, DATA_WIDTH)
)(
    input  wire                           clk,
    input  wire                           rst_n,        // synchronous reset, active low

    // Input links: a flit per port and clock in, a credit per port and clock back
    input  wire [N-1:0]                   in_valid,
    input  wire [N-1:0][FLIT_WIDTH-1:0]   in_flit,
    output wire [N-1:0]                   in_credit_valid,  // a slot of in_credit_vc is free
    output wire [N-1:0][VC_WIDTH-1:0]     in_credit_vc,

    // Output links
    output wire [N-1:0]                   out_valid,
    output wire [N-1:0][FLIT_WIDTH-1:0]   out_flit,
    input  wire [N-1:0]                   out_credit_valid,
    input  wire [N-1:0][VC_WIDTH-1:0]     out_credit_vc
);
    typedef `DC_NOC_FLIT_T(VC_WIDTH, DATA_WIDTH) flit_t;
    typedef `DC_NOC_HEAD_T(X_WIDTH, Y_WIDTH, DATA_WIDTH) head_t;

    `DC_STATIC_ASSERT(a_mesh_ports, N == NocPkg::MESH_PORTS)
    `DC_STATIC_ASSERT(a_route_fits, DATA_WIDTH > X_WIDTH + Y_WIDTH)
    `DC_STATIC_ASSERT(a_buf_depth, BUF_DEPTH >= 1)

    // XY route: the output port of a head flit with destination (x, y). West and south as
    // "not east, not here" (x < MY_X is constant on the west edge of the mesh).
    function automatic logic [2:0] xy_port(input logic [X_WIDTH-1:0] x,
                                           input logic [Y_WIDTH-1:0] y);
        if (x >  X_WIDTH'(MY_X)) return 3'(NocPkg::PORT_EAST);
        if (x != X_WIDTH'(MY_X)) return 3'(NocPkg::PORT_WEST);
        if (y >  Y_WIDTH'(MY_Y)) return 3'(NocPkg::PORT_NORTH);
        if (y != Y_WIDTH'(MY_Y)) return 3'(NocPkg::PORT_SOUTH);
        return 3'(NocPkg::PORT_LOCAL);
    endfunction

    // The route of the flit at each input, when it is a head flit.
    flit_t [N-1:0]      flit;
    head_t [N-1:0]      head;
    logic  [N-1:0][2:0] route;
    for (genvar i = 0; i < N; i++) begin: g_in
        assign flit[i]  = in_flit[i];
        assign head[i]  = flit[i].data;
        assign route[i] = xy_port(head[i].dest_x, head[i].dest_y);
    end

    // Placeholders, so the sketch elaborates: no buffering, straight through.
    /* verilator lint_off UNUSEDSIGNAL */
    logic unused;
    assign unused = clk ^ rst_n ^ (|out_credit_valid) ^ (|out_credit_vc) ^ (|route);
    /* verilator lint_on UNUSEDSIGNAL */
    assign in_credit_valid = '0;
    assign in_credit_vc    = '0;
    assign out_valid       = in_valid;
    assign out_flit        = in_flit;

endmodule

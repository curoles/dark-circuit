/* Mig6's network on chip, for now: two meshes of MESH_X x MESH_Y routers (NocMesh, one VC),
 * one for requests, one for answers (Mig6NocPkg; rtl/design/mig6/README.md).
 *
 * PE p's network interface joins node (p % MESH_X, p / MESH_X), the meshes' local port p:
 * its requests go into the request mesh, its answers come out of the answer mesh. The shared
 * memory's network interface is node (MEM_X, MEM_Y), past the top row: the north edge link
 * of column MEM_X in both meshes (NocMesh's y grows north). Every other edge link is tied
 * off (no flit in, no credit back); XY routes to nodes of the mesh and to the memory never
 * use them, so a flit leaving by one is a misroute (a_no_stray_flit), as a request coming
 * out at a PE's node is.
 *
 *            mem_req_fwd ^   v mem_rsp_fwd       request mesh: requests north to the memory
 *   +-------+       +-------+                    answer mesh:  answers from it, back down
 *   | 0,1   |<=====>| 1,1   |   PE 2, PE 3
 *   +-------+       +-------+
 *     ^ v             ^ v
 *   +-------+       +-------+
 *   | 0,0   |<=====>| 1,0   |   PE 0, PE 1
 *   +-------+       +-------+
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "dark_circuit_assert.svh"

module Mig6Noc import Mig6NocPkg::*; #(
    parameter Mig6ConfigPkg::mig6_cfg_t CFG = Mig6ConfigPkg::MIG6_CFG,  // see Mig6ConfigPkg
    parameter BUF_DEPTH  = 4,           // flits of a router's input buffer: credits
    parameter LINK_DELAY = 1            // clocks of each link between two routers
)(
    input  wire                        clk,
    input  wire                        rst_n,           // synchronous reset, active low
    // PE p's network interface
    input  req_link_fwd_t [N_PES-1:0]  pe_req_fwd,      // requests from it
    output link_bwd_t     [N_PES-1:0]  pe_req_bwd,      //   credits to it
    output rsp_link_fwd_t [N_PES-1:0]  pe_rsp_fwd,      // answers to it
    input  link_bwd_t     [N_PES-1:0]  pe_rsp_bwd,      //   credits from it
    // The shared memory's network interface
    output req_link_fwd_t              mem_req_fwd,     // requests to it
    input  link_bwd_t                  mem_req_bwd,     //   credits from it
    input  rsp_link_fwd_t              mem_rsp_fwd,     // answers from it
    output link_bwd_t                  mem_rsp_bwd      //   credits to it
);
    `DC_STATIC_ASSERT(a_mem_node, MEM_X < MESH_X && MEM_Y == MESH_Y)

    // When the routers' heads ask VC allocation (CFG.noc_route; kb rtl/design/mig6/noc_route).
    // @kb: rtl/design/mig6/noc_route
    localparam ROUTE = (CFG.noc_route == Mig6ConfigPkg::NOC_ROUTE_EARLY) ? NocPkg::ROUTE_EARLY
                                                                        : NocPkg::ROUTE_REGISTERED;
    // Who gives their heads the output VC (CFG.noc_alloc; kb rtl/design/mig6/noc_alloc).
    // @kb: rtl/design/mig6/noc_alloc
    localparam ALLOC = (CFG.noc_alloc == Mig6ConfigPkg::NOC_ALLOC_COMBINED) ? NocPkg::ALLOC_COMBINED
                                                                           : NocPkg::ALLOC_SEPARATE;

    // The edge links of the two meshes, per side. Only the memory's carry anything: the
    // others' credits are not read, nor their flits but for valid (a_no_stray_flit).
    /* verilator lint_off UNUSEDSIGNAL */
    req_link_fwd_t [MESH_X-1:0] req_north_in_fwd,  req_south_in_fwd;
    link_bwd_t     [MESH_X-1:0] req_north_in_bwd,  req_south_in_bwd;
    req_link_fwd_t [MESH_X-1:0] req_north_out_fwd, req_south_out_fwd;
    link_bwd_t     [MESH_X-1:0] req_north_out_bwd, req_south_out_bwd;
    req_link_fwd_t [MESH_Y-1:0] req_west_out_fwd,  req_east_out_fwd;
    link_bwd_t     [MESH_Y-1:0] req_west_in_bwd,   req_east_in_bwd;
    rsp_link_fwd_t [MESH_X-1:0] rsp_north_in_fwd,  rsp_south_in_fwd;
    link_bwd_t     [MESH_X-1:0] rsp_north_in_bwd,  rsp_south_in_bwd;
    rsp_link_fwd_t [MESH_X-1:0] rsp_north_out_fwd, rsp_south_out_fwd;
    rsp_link_fwd_t [MESH_Y-1:0] rsp_west_out_fwd,  rsp_east_out_fwd;
    link_bwd_t     [MESH_Y-1:0] rsp_west_in_bwd,   rsp_east_in_bwd;
    // Requests never go to a PE, answers never come from one.
    req_link_fwd_t [N_PES-1:0]  req_local_out_fwd;
    link_bwd_t     [N_PES-1:0]  rsp_local_in_bwd;
    /* verilator lint_on UNUSEDSIGNAL */
    // A flit out by a tied-off edge, or a request out at a PE.
    logic [2 * (2 * MESH_X + 2 * MESH_Y) + N_PES - 1:0] stray;

    // The memory's edge link: the north link of column MEM_X; the others carry nothing.
    for (genvar x = 0; x < MESH_X; x++) begin: g_north
        if (x == MEM_X) begin: g_mem
            assign mem_req_fwd          = req_north_out_fwd[x];
            assign req_north_out_bwd[x] = mem_req_bwd;
            assign rsp_north_in_fwd[x]  = mem_rsp_fwd;
            assign mem_rsp_bwd          = rsp_north_in_bwd[x];
        end else begin: g_tied
            assign req_north_out_bwd[x] = '0;
            assign rsp_north_in_fwd[x]  = '0;
        end
    end
    assign req_north_in_fwd  = '0;
    assign req_south_in_fwd  = '0;
    assign req_south_out_bwd = '0;
    assign rsp_south_in_fwd  = '0;

    NocMesh #(.X_SIZE(MESH_X), .Y_SIZE(MESH_Y), .X0(0), .Y0(0), .X_WIDTH(X_WIDTH),
              .Y_WIDTH(Y_WIDTH), .NUM_VCS(NUM_VCS), .BUF_DEPTH(BUF_DEPTH),
              .DATA_WIDTH(REQ_DATA_WIDTH), .LINK_DELAY(LINK_DELAY), .ROUTE(ROUTE),
              .ALLOC(ALLOC)) u_req_mesh(
        .clk, .rst_n,
        .local_in_fwd(pe_req_fwd), .local_in_bwd(pe_req_bwd),
        .local_out_fwd(req_local_out_fwd), .local_out_bwd('0),
        .north_in_fwd(req_north_in_fwd), .north_in_bwd(req_north_in_bwd),
        .north_out_fwd(req_north_out_fwd), .north_out_bwd(req_north_out_bwd),
        .south_in_fwd(req_south_in_fwd), .south_in_bwd(req_south_in_bwd),
        .south_out_fwd(req_south_out_fwd), .south_out_bwd(req_south_out_bwd),
        .west_in_fwd('0), .west_in_bwd(req_west_in_bwd),
        .west_out_fwd(req_west_out_fwd), .west_out_bwd('0),
        .east_in_fwd('0), .east_in_bwd(req_east_in_bwd),
        .east_out_fwd(req_east_out_fwd), .east_out_bwd('0));

    NocMesh #(.X_SIZE(MESH_X), .Y_SIZE(MESH_Y), .X0(0), .Y0(0), .X_WIDTH(X_WIDTH),
              .Y_WIDTH(Y_WIDTH), .NUM_VCS(NUM_VCS), .BUF_DEPTH(BUF_DEPTH),
              .DATA_WIDTH(RSP_DATA_WIDTH), .LINK_DELAY(LINK_DELAY), .ROUTE(ROUTE),
              .ALLOC(ALLOC)) u_rsp_mesh(
        .clk, .rst_n,
        .local_in_fwd('0), .local_in_bwd(rsp_local_in_bwd),
        .local_out_fwd(pe_rsp_fwd), .local_out_bwd(pe_rsp_bwd),
        .north_in_fwd(rsp_north_in_fwd), .north_in_bwd(rsp_north_in_bwd),
        .north_out_fwd(rsp_north_out_fwd), .north_out_bwd('0),
        .south_in_fwd(rsp_south_in_fwd), .south_in_bwd(rsp_south_in_bwd),
        .south_out_fwd(rsp_south_out_fwd), .south_out_bwd('0),
        .west_in_fwd('0), .west_in_bwd(rsp_west_in_bwd),
        .west_out_fwd(rsp_west_out_fwd), .west_out_bwd('0),
        .east_in_fwd('0), .east_in_bwd(rsp_east_in_bwd),
        .east_out_fwd(rsp_east_out_fwd), .east_out_bwd('0));

    // Flits out by a tied-off edge (every edge of both meshes but the memory's request link)
    // or by a PE's port of the request mesh.
    for (genvar x = 0; x < MESH_X; x++) begin: g_stray_x
        assign stray[x]              = (x != MEM_X) && req_north_out_fwd[x].valid;
        assign stray[MESH_X + x]     = req_south_out_fwd[x].valid;
        assign stray[2 * MESH_X + x] = rsp_north_out_fwd[x].valid;
        assign stray[3 * MESH_X + x] = rsp_south_out_fwd[x].valid;
    end
    for (genvar y = 0; y < MESH_Y; y++) begin: g_stray_y
        assign stray[4 * MESH_X + y]              = req_west_out_fwd[y].valid;
        assign stray[4 * MESH_X + MESH_Y + y]     = req_east_out_fwd[y].valid;
        assign stray[4 * MESH_X + 2 * MESH_Y + y] = rsp_west_out_fwd[y].valid;
        assign stray[4 * MESH_X + 3 * MESH_Y + y] = rsp_east_out_fwd[y].valid;
    end
    for (genvar p = 0; p < N_PES; p++) begin: g_stray_pe
        assign stray[4 * MESH_X + 4 * MESH_Y + p] = req_local_out_fwd[p].valid;
    end

    `DC_ASSERT(a_no_stray_flit, stray == '0)

endmodule

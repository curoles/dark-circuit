/* Mig6's grid of PEs: N_PES Mig6Pe on Mig6Noc's two meshes, the edge link to what sits at
 * the grid's edge (the shared memory) as ports.
 *
 * PE p is hart p (HART_ID p) at node (p % MESH_X, p / MESH_X) of the meshes, their local
 * port p (Mig6NocPkg: NocMesh's coordinates, y grows north); the coordinates are computed
 * here only, so a PE and its node always agree. The edge link is Mig6Noc's: the requests to
 * the shared memory, node (MEM_X, MEM_Y) past the top row, and the answers from it. A bigger
 * grid is Mig6NocPkg's MESH_X and MESH_Y. Each PE's debug port and traces come out as arrays,
 * PE p at index p.
 *
 *   PE 0 .. N_PES-1 (Mig6Pe g_pe[p].u_pe) <==> Mig6Noc u_noc <== edge: mem_req_*, mem_rsp_*
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

module Mig6PeGrid import Mig6Pkg::*, Mig6NocPkg::*; #(
    parameter mig6_cfg_t CFG        = MIG6_CFG, // configuration, see Mig6ConfigPkg
    parameter            BUF_DEPTH  = 4,        // the routers' input buffers: credits
    parameter            LINK_DELAY = 1         // clocks of a link between two routers
)(
    input  wire                        clk,
    input  wire                        rst_n,       // synchronous reset, active low
    // PE p: its debug port and traces
    output wire           [N_PES-1:0]  halt,        // halted at EBREAK
    output retire_t       [N_PES-1:0]  retire,      // for trace in testbench
    output pipe_trace_t   [N_PES-1:0]  pipe_trace,  // pipeline view for testbench
    input  dbg_req_t      [N_PES-1:0]  dbg_req,     // debug, used while halted
    output dbg_rsp_t      [N_PES-1:0]  dbg_rsp,
    // The edge link: the shared memory's network interface
    output req_link_fwd_t              mem_req_fwd, // requests to it
    input  link_bwd_t                  mem_req_bwd, //   credits from it
    input  rsp_link_fwd_t              mem_rsp_fwd, // answers from it
    output link_bwd_t                  mem_rsp_bwd  //   credits to it
);
    req_link_fwd_t [N_PES-1:0] pe_req_fwd;
    link_bwd_t     [N_PES-1:0] pe_req_bwd;
    rsp_link_fwd_t [N_PES-1:0] pe_rsp_fwd;
    link_bwd_t     [N_PES-1:0] pe_rsp_bwd;

    for (genvar p = 0; p < N_PES; p++) begin: g_pe
        Mig6Pe #(.CFG(CFG), .HART_ID(word_t'(p)), .MY_PE_GRID_X(X_WIDTH'(p % MESH_X)),
                 .MY_PE_GRID_Y(Y_WIDTH'(p / MESH_X)), .NOC_BUF_DEPTH(BUF_DEPTH)) u_pe(
            .clk, .rst_n, .halt(halt[p]), .retire(retire[p]), .pipe_trace(pipe_trace[p]),
            .dbg_req(dbg_req[p]), .dbg_rsp(dbg_rsp[p]),
            .noc_req_fwd(pe_req_fwd[p]), .noc_req_bwd(pe_req_bwd[p]),
            .noc_rsp_fwd(pe_rsp_fwd[p]), .noc_rsp_bwd(pe_rsp_bwd[p]));
    end

    Mig6Noc #(.BUF_DEPTH(BUF_DEPTH), .LINK_DELAY(LINK_DELAY)) u_noc(
        .clk, .rst_n, .pe_req_fwd, .pe_req_bwd, .pe_rsp_fwd, .pe_rsp_bwd,
        .mem_req_fwd, .mem_req_bwd, .mem_rsp_fwd, .mem_rsp_bwd);

endmodule

/* Allocation of the NoC router with virtual channels: VC allocation and switch allocation of
 * all its ports, from the input VCs' requests, wiring only.
 *
 * The input VCs ask (NocVirtChIn's requests): va_req, an output VC of a port, for a head;
 * sa_req, the switch to a port on an output VC, for an active VC with a flit. VC allocation
 * (NocVirtChAlloc) answers a VA request with a free output VC of its port (vc_grant to the
 * input VC, vc_alloc to the output VC); switch allocation (NocSwitchAlloc) lets SA requests
 * whose output VC has a credit send, one flit per input and per output each clock (pop to the
 * input unit, the crossbar's selects). One part for both, so that a variant that couples the
 * two allocations changes only this part, not the router's wiring. The allocators read only
 * the requests and the output VCs' state (free, has_credit), never the input VCs' states.
 *
 * ALLOC chooses who gives the output VCs: NocPkg::ALLOC_SEPARATE, VC allocation (a head gets
 * its VC, then asks the switch in a later clock); NocPkg::ALLOC_COMBINED, switch allocation
 * itself (a head asks the switch with need_vc and is given the free VC of its port with a
 * credit as it wins: no VC allocator, a clock less; valid for deterministic routing with any
 * free VC of the port allowed, NocVirtChRouter's assumption; kb
 * rtl/lib/block/noc/combined_alloc).
 *
 *   ALLOC_SEPARATE:
 *   va_req[p][v] ------> NocVirtChAlloc ------> vc_grant[p][v], vc_alloc[r][w]
 *   out_vc_state[r][w] -+  (free)
 *                       +> (free, has_credit)
 *   sa_req[p][v] ------> NocSwitchAlloc ------> pop[p], xbar_sel[r], xbar_valid[r]
 *   ALLOC_COMBINED: no NocVirtChAlloc; NocSwitchAlloc's vc_grant, vc_alloc (heads' need_vc)
 *
 * One file for the behave and the struct library: the allocators it is built with give the
 * version.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "dark_circuit_assert.svh"
`include "../block/noc/dark_circuit_noc.svh"

module NocVirtChRtrAlloc #(
    parameter  N          = NocPkg::MESH_PORTS, // ports: inputs and outputs
    parameter  NUM_VCS    = 2,                  // virtual channels on every link
    parameter  ALLOC      = NocPkg::ALLOC_SEPARATE,     // who gives the output VCs
    localparam VC_WIDTH   = `DC_NOC_VC_WIDTH(NUM_VCS),
    localparam PORT_WIDTH = `DC_NOC_PORT_WIDTH(N),
    localparam type VC_VLD_T   = `DC_NOC_VC_VLD_T(VC_WIDTH),
    localparam type VA_REQ_T   = `DC_NOC_VA_REQ_T(PORT_WIDTH),
    localparam type SA_REQ_T   = `DC_NOC_SA_REQ_T(PORT_WIDTH, VC_WIDTH)
)(
    input  wire                                           clk,
    input  wire                                           rst_n,        // synchronous, active low
    // (Not read with ALLOC_COMBINED: no VC allocation; the input VCs never make them.)
    /* verilator lint_off UNUSEDSIGNAL */
    input  VA_REQ_T               [N-1:0][NUM_VCS-1:0]    va_req,       // input VCs: a VC of a port
    /* verilator lint_on UNUSEDSIGNAL */
    input  SA_REQ_T               [N-1:0][NUM_VCS-1:0]    sa_req,       // ... the switch
    input  NocPkg::vc_out_state_t [N-1:0][NUM_VCS-1:0]    out_vc_state, // output VCs: free, credit
    output VC_VLD_T               [N-1:0][NUM_VCS-1:0]    vc_grant,     // to an input VC: its VC
    output logic                  [N-1:0][NUM_VCS-1:0]    vc_alloc,     // an output VC taken
    output VC_VLD_T               [N-1:0]                 pop,          // per input: VC that sends
    output logic                  [N-1:0][PORT_WIDTH-1:0] xbar_sel,     // per output: its input
    output logic                  [N-1:0]                 xbar_valid    // per output: a flit goes
);
    `DC_STATIC_ASSERT(a_alloc, ALLOC == NocPkg::ALLOC_SEPARATE || ALLOC == NocPkg::ALLOC_COMBINED)

    // Switch allocation's VCs (heads' need_vc): not read with ALLOC_SEPARATE (no need_vc).
    /* verilator lint_off UNUSEDSIGNAL */
    VC_VLD_T [N-1:0][NUM_VCS-1:0] sw_vc_grant;
    logic    [N-1:0][NUM_VCS-1:0] sw_vc_alloc;
    /* verilator lint_on UNUSEDSIGNAL */

    // Switch allocation: the flits that cross the crossbar this clock (and, combined, the
    // heads' output VCs).
    // @kb: rtl/lib/block/noc/allocation
    NocSwitchAlloc #(.N(N), .NUM_VCS(NUM_VCS)) u_sw_alloc(
        .clk, .rst_n, .sa_req, .out_vc_state, .pop, .xbar_sel, .xbar_valid,
        .vc_grant(sw_vc_grant), .vc_alloc(sw_vc_alloc));

    // Who gives the output VCs.
    // @kb: rtl/lib/block/noc/combined_alloc
    if (ALLOC == NocPkg::ALLOC_COMBINED) begin: g_combined
        assign vc_grant = sw_vc_grant;
        assign vc_alloc = sw_vc_alloc;
    end else begin: g_separate
        // VC allocation: a head gets a free output VC of its port.
        NocVirtChAlloc #(.N(N), .NUM_VCS(NUM_VCS)) u_vc_alloc(
            .clk, .rst_n, .va_req, .out_vc_state, .vc_grant, .vc_alloc);
    end

endmodule

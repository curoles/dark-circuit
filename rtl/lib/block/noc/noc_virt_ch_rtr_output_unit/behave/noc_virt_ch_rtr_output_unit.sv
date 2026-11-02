/* Output unit of the NoC router with virtual channels, behavioral: one output port.
 *
 * The output side keeps no flits, only the state of the next router's input VCs, one
 * NocVirtChOut per VC (a credit count and whether a packet holds the VC). The unit follows the
 * port's link: a flit sent on out_fwd is a send on its VC (and a tail frees the VC), a credit
 * on out_bwd comes back to its VC; VC allocation takes a free VC (vc_alloc). The state of every
 * VC goes to the allocators (vc_state).
 *
 *   out_fwd (valid, vc, tail) ---> by vc ---> send[v], send_tail[v] ---+
 *   out_bwd (valid, vc) ----------> by vc ---> credit[v] ---------------+
 *   vc_alloc[v] --------------------------------------------------------+
 *                                                                       v
 *                                            +------------------+
 *                                            | NocVirtChOut [v] |---> vc_state[v]
 *                                            |  [NUM_VCS]       |     (free, has_credit)
 *                                            +------------------+
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "../block/noc/dark_circuit_noc.svh"

module NocVirtChRtrOutputUnit #(
    parameter  NUM_VCS    = 2,                  // virtual channels of the link
    parameter  BUF_DEPTH  = 4,                  // the next router's buffer per VC: credits
    parameter  DATA_WIDTH = 32,                 // data of a flit
    localparam VC_WIDTH   = `DC_NOC_VC_WIDTH(NUM_VCS),
    localparam type LINK_FWD_T = `DC_NOC_LINK_FWD_T(VC_WIDTH, DATA_WIDTH),
    localparam type LINK_BWD_T = `DC_NOC_LINK_BWD_T(VC_WIDTH)
)(
    input  wire                                 clk,
    input  wire                                 rst_n,      // synchronous reset, active low
    // The port's link: the flits sent (only valid, vc and tail are read) and the credits back
    /* verilator lint_off UNUSEDSIGNAL */
    input  LINK_FWD_T                           out_fwd,
    /* verilator lint_on UNUSEDSIGNAL */
    input  LINK_BWD_T                           out_bwd,
    input  wire        [NUM_VCS-1:0]            vc_alloc,   // VC allocation takes a VC
    output NocPkg::vc_out_state_t [NUM_VCS-1:0] vc_state    // every VC: free, has_credit
);
    for (genvar v = 0; v < NUM_VCS; v++) begin: g_vc
        logic send;         // a flit goes out on this VC

        assign send = out_fwd.valid && out_fwd.flit.vc == VC_WIDTH'(v);

        NocVirtChOut #(.BUF_DEPTH(BUF_DEPTH)) u_vc(
            .clk, .rst_n, .alloc(vc_alloc[v]), .send, .send_tail(send && out_fwd.flit.tail),
            .credit(out_bwd.valid && out_bwd.vc == VC_WIDTH'(v)), .state(vc_state[v]));
    end

endmodule

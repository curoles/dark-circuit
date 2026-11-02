/* Output unit of the NoC router with virtual channels, made of blocks and gates: one output port.
 *
 * Same ports, parameters and behavior as the behave version (see there). The vc of the flit
 * sent and of the credit back are decoded (Decoder, enabled by their valid) into a send and a
 * credit per VC; a send is a tail send when the flit is a tail (And2 with tail on every bit).
 *
 *   out_fwd.vc --> Decoder (en: out_fwd.valid) --> send --+--> And2 (tail) --> send_tail
 *   out_bwd.vc --> Decoder (en: out_bwd.valid) --> credit  |
 *   send[v], send_tail[v], credit[v], vc_alloc[v] --> NocVirtChOut [v] --> vc_state[v]
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
    localparam VC_N = 1 << VC_WIDTH;            // outputs of a vc decoder

    // The decoders' outputs above NUM_VCS - 1 are never set (the vc names a VC).
    /* verilator lint_off UNUSEDSIGNAL */
    wire [VC_N-1:0]    send_vc;                 // per VC: a flit goes out on it
    wire [VC_N-1:0]    credit_vc;               // per VC: a credit comes back for it
    /* verilator lint_on UNUSEDSIGNAL */
    wire [NUM_VCS-1:0] send_tail;               // per VC: the flit sent is a tail

    Decoder #(.SIZE(VC_WIDTH)) u_decoder_send(.in(out_fwd.flit.vc), .en(out_fwd.valid),
                                              .out(send_vc));
    Decoder #(.SIZE(VC_WIDTH)) u_decoder_credit(.in(out_bwd.vc), .en(out_bwd.valid),
                                                .out(credit_vc));
    And2 #(NUM_VCS) u_and2_send_tail(
        .in1(send_vc[NUM_VCS-1:0]), .in2({NUM_VCS{out_fwd.flit.tail}}), .out(send_tail));

    for (genvar v = 0; v < NUM_VCS; v++) begin: g_vc
        NocVirtChOut #(.BUF_DEPTH(BUF_DEPTH)) u_vc(
            .clk, .rst_n, .alloc(vc_alloc[v]), .send(send_vc[v]), .send_tail(send_tail[v]),
            .credit(credit_vc[v]), .state(vc_state[v]));
    end

endmodule

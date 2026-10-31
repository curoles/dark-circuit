/* NoC link: the wires from a router's output port to the next router's input port, DELAY clocks
 * each way.
 *
 * Forward: the flits, from the sending router (src_fwd, its out_fwd) to the receiving one
 * (dst_fwd, its in_fwd); backward: the credits, from the receiving router (dst_bwd, its in_bwd)
 * to the sending one (src_bwd, its out_bwd). DELAY = 0: plain wires; DELAY > 0: registers
 * (DelayLine), as on a long wire. Valid bits go through stages with reset, the flit and the
 * credit's vc through stages without (they mean nothing while not valid). The delay counts
 * twice in the credit round trip, flit forward and credit back: a VC streams a flit every clock
 * only when its buffer (BUF_DEPTH) covers the whole round trip. Routers are always connected
 * through a NocLinkWire, also with DELAY 0, so a mesh can give its links any delay.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "../block/noc/dark_circuit_noc.svh"

module NocLinkWire #(
    parameter  DELAY      = 1,                  // clocks each way; 0: wires
    parameter  NUM_VCS    = 2,                  // virtual channels of the link
    parameter  DATA_WIDTH = 32,                 // data of a flit
    localparam VC_WIDTH   = `DC_NOC_VC_WIDTH(NUM_VCS),
    localparam type FLIT_T     = `DC_NOC_FLIT_T(VC_WIDTH, DATA_WIDTH),
    localparam type LINK_FWD_T = `DC_NOC_LINK_FWD_T(VC_WIDTH, DATA_WIDTH),
    localparam type LINK_BWD_T = `DC_NOC_LINK_BWD_T(VC_WIDTH)
)(
    input  wire       clk,
    input  wire       rst_n,                    // synchronous reset, active low
    input  LINK_FWD_T src_fwd,                  // from the sending router: flits
    output LINK_BWD_T src_bwd,                  //   to it: credits
    output LINK_FWD_T dst_fwd,                  // to the receiving router: flits
    input  LINK_BWD_T dst_bwd                   //   from it: credits
);
    // Flits forward.
    DelayLine  #(.WIDTH(1), .DEPTH(DELAY), .RESET(1)) u_fwd_valid(
        .clk, .rst_n, .in(src_fwd.valid), .out(dst_fwd.valid));
    DelayLineT #(.T(FLIT_T), .DEPTH(DELAY)) u_fwd_flit(
        .clk, .rst_n, .in(src_fwd.flit), .out(dst_fwd.flit));

    // Credits backward.
    DelayLine  #(.WIDTH(1), .DEPTH(DELAY), .RESET(1)) u_bwd_valid(
        .clk, .rst_n, .in(dst_bwd.valid), .out(src_bwd.valid));
    DelayLine  #(.WIDTH(VC_WIDTH), .DEPTH(DELAY)) u_bwd_vc(
        .clk, .rst_n, .in(dst_bwd.vc), .out(src_bwd.vc));

endmodule

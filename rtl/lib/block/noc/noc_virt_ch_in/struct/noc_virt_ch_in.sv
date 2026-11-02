/* NoC virtual channel, the input end: one VC of an input port, made of blocks and gates.
 *
 * Same ports, parameters and behavior as the behave version (see there). Each transition
 * starts in a state of its own, so at most one happens in a clock: they are one-hot, and the
 * state register loads the target of the one that happens (Mux1hot3 of the NocPkg names, so the
 * wiring does not depend on their numbering), enabled by any of them (Or3).
 *
 *   push --> write +-------+ data_out --> front.flit (head, tail)
 *   pop ---> read  | FifoT | empty --> Inv --> front.valid, has_flit
 *                  +-------+
 *
 *   state_q --> CmpEq VC_IDLE, VC_WAIT_VC, VC_ACTIVE --> is_idle, is_wait, is_active
 *   start   = And3(is_idle, front.valid, head) ---> en of route_q  (DffEn: front_route)
 *   granted = And2(is_wait, grant.valid) ---------> en of out_vc_q (DffEn: grant.vc)
 *   done    = And3(is_active, pop, tail)
 *
 *   start   --> sel[0] +----------+ in0: VC_WAIT_VC     +--------------+
 *   granted --> sel[1] | Mux1hot3 | in1: VC_ACTIVE  --->| DffSyncRstEn |--> state_q
 *   done    --> sel[2] +----------+ in2: VC_IDLE   en ->| (VC_IDLE)    |
 *   start, granted, done --> Or3 -----------------------+--------------+
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "dark_circuit_assert.svh"
`include "../block/noc/dark_circuit_noc.svh"

module NocVirtChIn #(
    parameter  VC_WIDTH   = 1,
    parameter  DATA_WIDTH = 32,
    parameter  BUF_DEPTH  = 4,                  // flits; the sender's credits start here
    parameter  PORT_WIDTH = 3,                  // bits of an output port number
    localparam type FLIT_T     = `DC_NOC_FLIT_T(VC_WIDTH, DATA_WIDTH),
    localparam type FLIT_VLD_T = `DC_NOC_FLIT_VLD_T(VC_WIDTH, DATA_WIDTH),
    localparam type VC_VLD_T   = `DC_NOC_VC_VLD_T(VC_WIDTH),
    localparam type STATE_T    = `DC_NOC_VC_IN_STATE_T(PORT_WIDTH, VC_WIDTH)
)(
    input  wire                  clk,
    input  wire                  rst_n,         // synchronous reset, active low
    input  FLIT_VLD_T            push,          // a flit of this VC comes in on the link
    input  wire                  pop,           // switch allocation sends the front flit
    output FLIT_VLD_T            front,         // the flit at the front; valid: not empty
    input  wire [PORT_WIDTH-1:0] front_route,   // route of the front flit, when it is a head
    input  VC_VLD_T              grant,         // VC allocation: the packet's output VC
    output STATE_T               state          // state, flit, route, output VC: for allocators
);
    // FifoT holds a power of 2 entries, at least 2: BUF_DEPTH rounded up.
    localparam BUF_ADDR_WIDTH = (BUF_DEPTH > 1) ? $clog2(BUF_DEPTH) : 1;

    `DC_STATIC_ASSERT(a_buf_depth, BUF_DEPTH >= 1)

    FLIT_T                    front_flit;
    wire                      empty;
    wire                      has_flit;         // not empty: front is valid
    // Status the credits make unnecessary (full is only checked).
    /* verilator lint_off UNUSEDSIGNAL */
    wire                      full;
    wire [BUF_ADDR_WIDTH:0]   count;
    wire                      almost_full;
    wire                      almost_empty;
    /* verilator lint_on UNUSEDSIGNAL */
    wire [1:0]                state_q;
    wire                      is_idle;
    wire                      is_wait;
    wire                      is_active;
    wire                      start;            // a head at the front of an idle VC
    wire                      granted;          // VC allocation answers the waiting packet
    wire                      done;             // its tail is sent
    wire                      state_en;         // one of the three: the state moves
    wire [1:0]                state_next;       // the target of the one that happens
    wire [PORT_WIDTH-1:0]     route_q;
    wire [VC_WIDTH-1:0]       out_vc_q;

    FifoT #(.T(FLIT_T), .ADDR_WIDTH(BUF_ADDR_WIDTH)) u_buf(
        .clk, .rst_n, .write(push.valid), .data_in(push.flit), .read(pop),
        .data_out(front_flit), .empty, .full, .count, .almost_full, .almost_empty);
    Inv #(1) u_inv_has_flit(.in(empty), .out(has_flit));

    assign front.valid = has_flit;
    assign front.flit  = front_flit;

    CmpEq #(2) u_cmp_eq_idle  (.in1(state_q), .in2(NocPkg::VC_IDLE),    .eq(is_idle));
    CmpEq #(2) u_cmp_eq_wait  (.in1(state_q), .in2(NocPkg::VC_WAIT_VC), .eq(is_wait));
    CmpEq #(2) u_cmp_eq_active(.in1(state_q), .in2(NocPkg::VC_ACTIVE),  .eq(is_active));

    And3 #(1) u_and3_start  (.in1(is_idle), .in2(has_flit), .in3(front_flit.head), .out(start));
    And2 #(1) u_and2_granted(.in1(is_wait), .in2(grant.valid), .out(granted));
    And3 #(1) u_and3_done   (.in1(is_active), .in2(pop), .in3(front_flit.tail), .out(done));

    Mux1hot3 #(2) u_mux1hot3_state_next(
        .in0(NocPkg::VC_WAIT_VC), .in1(NocPkg::VC_ACTIVE), .in2(NocPkg::VC_IDLE),
        .sel({done, granted, start}), .out(state_next));
    Or3 #(1) u_or3_state_en(.in1(start), .in2(granted), .in3(done), .out(state_en));
    DffSyncRstEn #(.WIDTH(2), .RST_VAL(NocPkg::VC_IDLE)) u_dff_sync_rst_en_state(
        .clk, .rst_n, .en(state_en), .in(state_next), .out(state_q));

    DffEn #(PORT_WIDTH) u_dff_en_route (.clk, .en(start),   .in(front_route), .out(route_q));
    DffEn #(VC_WIDTH)   u_dff_en_out_vc(.clk, .en(granted), .in(grant.vc),    .out(out_vc_q));

    assign state.state    = state_q;
    assign state.has_flit = has_flit;
    assign state.route    = route_q;
    assign state.out_vc   = out_vc_q;

    // The protocol around the VC, as in the behave version.
    `DC_ASSERT(a_no_push_when_full, !(push.valid && full))
    `DC_ASSERT(a_idle_front_is_head, !(is_idle && has_flit && !front_flit.head))
    `DC_ASSERT(a_grant_when_waiting, !grant.valid || is_wait)
    `DC_ASSERT(a_pop_when_active, !pop || (is_active && has_flit))

endmodule

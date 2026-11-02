/* Switch allocation of the NoC router, made of blocks and gates.
 *
 * Same ports, parameters and behavior as the behave version (see there). An input VC's credit
 * is picked in two steps, the credits of its route's port, then the bit of its output VC (one
 * MuxN on route * NUM_VCS + out_vc would need a multiplier when NUM_VCS is not a power of 2).
 * A one-hot pick or grant becomes an index with a PriorityEncoder (the index of its one bit),
 * whose valid says there is one. A pick's route, decoded (Decoder, enabled by "a pick"), is
 * what the input wants of every output port at once.
 *
 *   per input VC (p, v):
 *     credit --> MuxN (sel: route) --> MuxN (sel: out_vc) --> its credit --+
 *     state --> CmpEq VC_ACTIVE ---------------------------------------->+--> And3 --> eligible
 *     has_flit ------------------------------------------------------------+
 *   per input port p, stage 1:
 *     eligible --> RoundRobinArbiter (advance: won[p]) --> pick[p] (one-hot)
 *     pick[p] --> PriorityEncoder --> pick_vc[p], has_pick[p]
 *     routes --> MuxN (sel: pick_vc[p]) --> pick_route[p]
 *     pick_route[p] --> Decoder (en: has_pick[p]) --> want[r][p], every output port r
 *   per output port r, stage 2:
 *     want[r] --> RoundRobinArbiter --> win[r] --> PriorityEncoder --> xbar_sel[r], xbar_valid[r]
 *   per input port p:
 *     win[r][p], every r --> OrReduce --> won[p]: pop[p] = {won[p], pick_vc[p]}
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "dark_circuit_assert.svh"
`include "../block/noc/dark_circuit_noc.svh"

module NocSwitchAlloc #(
    parameter  N          = NocPkg::MESH_PORTS, // ports: inputs and outputs
    parameter  NUM_VCS    = 2,                  // virtual channels on every link
    localparam VC_WIDTH   = `DC_NOC_VC_WIDTH(NUM_VCS),
    localparam PORT_WIDTH = `DC_NOC_PORT_WIDTH(N),
    localparam type VC_VLD_T   = `DC_NOC_VC_VLD_T(VC_WIDTH),
    localparam type VC_STATE_T = `DC_NOC_VC_IN_STATE_T(PORT_WIDTH, VC_WIDTH)
)(
    input  wire                                        clk,
    input  wire                                        rst_n,        // synchronous, active low
    input  VC_STATE_T             [N-1:0][NUM_VCS-1:0] in_vc_state,  // active, a flit, route, VC
    input  NocPkg::vc_out_state_t [N-1:0][NUM_VCS-1:0] out_vc_state, // has_credit
    output VC_VLD_T               [N-1:0]              pop,          // per input: VC that sends
    output logic                  [N-1:0][PORT_WIDTH-1:0] xbar_sel,  // per output: its input
    output logic                  [N-1:0]              xbar_valid    // per output: a flit goes
);
    localparam VC_N   = 1 << VC_WIDTH;          // inputs of a VC encoder
    localparam PORT_N = 1 << PORT_WIDTH;        // inputs of a port encoder, outputs of a decoder

    wire [N-1:0][NUM_VCS-1:0]    credit;        // per output port: the credits of its VCs
    wire [N-1:0][NUM_VCS-1:0]    pick;          // per input: one-hot, its stage-1 pick
    wire [N-1:0]                 has_pick;
    wire [N-1:0][VC_WIDTH-1:0]   pick_vc;       // per input: the VC of its pick
    wire [N-1:0][PORT_WIDTH-1:0] pick_route;    // per input: the output its pick wants
    wire [N-1:0][N-1:0]          want;          // per output: the inputs whose pick wants it
    wire [N-1:0][N-1:0]          win;           // per output: one-hot, the input it takes
    wire [N-1:0]                 won;           // per input: its pick won at its output

    for (genvar r = 0; r < N; r++) begin: g_credit_port
        for (genvar w = 0; w < NUM_VCS; w++) begin: g_credit_vc
            // Only has_credit is read here (free: VC allocation).
            /* verilator lint_off UNUSEDSIGNAL */
            NocPkg::vc_out_state_t o;
            /* verilator lint_on UNUSEDSIGNAL */

            assign o            = out_vc_state[r][w];
            assign credit[r][w] = o.has_credit;
        end
    end

    // Stage 1: each input port picks one of its eligible VCs.
    for (genvar p = 0; p < N; p++) begin: g_in_port
        wire [NUM_VCS-1:0]                 eligible;
        wire [NUM_VCS-1:0][PORT_WIDTH-1:0] routes;  // the route of each VC
        // The decoder's outputs at N and above are never set (a route is a port).
        /* verilator lint_off UNUSEDSIGNAL */
        wire [PORT_N-1:0]                  want_of;
        /* verilator lint_on UNUSEDSIGNAL */

        for (genvar v = 0; v < NUM_VCS; v++) begin: g_in_vc
            VC_STATE_T         s;
            wire               active;
            wire [NUM_VCS-1:0] port_credit;     // the credits of its route's port
            wire               vc_credit;       // ... of its output VC

            assign s         = in_vc_state[p][v];
            assign routes[v] = s.route;
            CmpEq #(2) u_cmp_eq_active(.in1(s.state), .in2(NocPkg::VC_ACTIVE), .eq(active));
            MuxN #(.N(N), .WIDTH(NUM_VCS)) u_mux_n_port_credit(
                .in(credit), .sel(s.route), .out(port_credit));
            if (NUM_VCS == 1) begin: g_one_vc
                assign vc_credit = port_credit[0];
            end else begin: g_vcs
                MuxN #(.N(NUM_VCS), .WIDTH(1)) u_mux_n_vc_credit(
                    .in(port_credit), .sel(s.out_vc), .out(vc_credit));
            end
            And3 #(1) u_and3_eligible(.in1(active), .in2(s.has_flit), .in3(vc_credit),
                                      .out(eligible[v]));
        end

        // One VC: it is the pick when eligible (an arbiter needs two requesters).
        if (NUM_VCS == 1) begin: g_one_vc
            assign pick[p]       = eligible;
            assign has_pick[p]   = eligible[0];
            assign pick_vc[p]    = '0;
            assign pick_route[p] = routes[0];
        end else begin: g_arbiter
            RoundRobinArbiter #(.N(NUM_VCS)) u_in_arbiter(
                .clk, .rst_n, .req(eligible), .advance(won[p]), .grant(pick[p]));
            PriorityEncoder #(.SIZE(VC_WIDTH)) u_priority_encoder_pick(
                .in(VC_N'(pick[p])), .out(pick_vc[p]), .valid(has_pick[p]));
            MuxN #(.N(NUM_VCS), .WIDTH(PORT_WIDTH)) u_mux_n_pick_route(
                .in(routes), .sel(pick_vc[p]), .out(pick_route[p]));
        end

        Decoder #(.SIZE(PORT_WIDTH)) u_decoder_want(.in(pick_route[p]), .en(has_pick[p]),
                                                   .out(want_of));
        for (genvar r = 0; r < N; r++) begin: g_want
            assign want[r][p] = want_of[r];
        end
    end

    // Stage 2: each output port picks one of the inputs whose pick wants it.
    for (genvar r = 0; r < N; r++) begin: g_out_port
        RoundRobinArbiter #(.N(N)) u_out_arbiter(
            .clk, .rst_n, .req(want[r]), .advance(1'b1), .grant(win[r]));
        PriorityEncoder #(.SIZE(PORT_WIDTH)) u_priority_encoder_sel(
            .in(PORT_N'(win[r])), .out(xbar_sel[r]), .valid(xbar_valid[r]));
    end

    // An input sends when its pick won (at one output: the pick wants one).
    for (genvar p = 0; p < N; p++) begin: g_pop
        wire [N-1:0] won_at;                    // per output: it took this input
        VC_VLD_T     g;

        for (genvar r = 0; r < N; r++) begin: g_won_at
            assign won_at[r] = win[r][p];
        end
        OrReduce #(N) u_or_reduce_won(.in(won_at), .out(won[p]));
        assign g.valid = won[p];
        assign g.vc    = pick_vc[p];
        assign pop[p]  = g;

        `DC_ASSERT(a_wins_one_output, $onehot0(won_at))
    end

endmodule

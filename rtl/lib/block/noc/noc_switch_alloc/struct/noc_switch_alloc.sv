/* Switch allocation of the NoC router, made of blocks and gates.
 *
 * Same ports, parameters and behavior as the behave version (see there). An input VC's credit
 * is picked in two steps, the credits of its request's port, then the bit of its output VC (one
 * MuxN on port * NUM_VCS + vc would need a multiplier when NUM_VCS is not a power of 2).
 * A one-hot pick or grant becomes an index with a PriorityEncoder (the index of its one bit),
 * whose valid says there is one. A pick's route, decoded (Decoder, enabled by "a pick"), is
 * what the input wants of every output port at once. A head's request (need_vc) is eligible
 * when its port has a free VC with a credit (per output port: And2 of free and has_credit per
 * VC, a PriorityEncoder giving the highest, its valid: there is one; MuxN on the request's
 * port, Mux2 by need_vc against its own VC's credit); the winner's need (MuxN by pick_vc)
 * gates a Decoder of the free VC (vc_alloc) and of pick_vc (vc_grant, its vc the free VC of
 * the pick's route: MuxN).
 *
 *   per input VC (p, v):
 *     credit --> MuxN (sel: sa_req.port) --> MuxN (sel: sa_req.vc) --> its credit --+
 *     sa_req.valid ------------------------------------------------------------>+--> And2
 *                                                                                     --> eligible
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
    localparam type SA_REQ_T   = `DC_NOC_SA_REQ_T(PORT_WIDTH, VC_WIDTH)
)(
    input  wire                                        clk,
    input  wire                                        rst_n,        // synchronous, active low
    input  SA_REQ_T               [N-1:0][NUM_VCS-1:0] sa_req,       // input VCs: port, output VC
    input  NocPkg::vc_out_state_t [N-1:0][NUM_VCS-1:0] out_vc_state, // free, has_credit
    output VC_VLD_T               [N-1:0]              pop,          // per input: VC that sends
    output logic                  [N-1:0][PORT_WIDTH-1:0] xbar_sel,  // per output: its input
    output logic                  [N-1:0]              xbar_valid,   // per output: a flit goes
    output VC_VLD_T               [N-1:0][NUM_VCS-1:0] vc_grant,     // to a head: its output VC
    output logic                  [N-1:0][NUM_VCS-1:0] vc_alloc      // an output VC taken
);
    localparam VC_N   = 1 << VC_WIDTH;          // inputs of a VC encoder
    localparam PORT_N = 1 << PORT_WIDTH;        // inputs of a port encoder, outputs of a decoder

    wire [N-1:0][NUM_VCS-1:0]    credit;        // per output port: the credits of its VCs
    wire [N-1:0]                 has_pick;
    wire [N-1:0][VC_WIDTH-1:0]   pick_vc;       // per input: the VC of its pick
    wire [N-1:0][PORT_WIDTH-1:0] pick_route;    // per input: the output its pick wants
    wire [N-1:0][N-1:0]          want;          // per output: the inputs whose pick wants it
    wire [N-1:0][N-1:0]          win;           // per output: one-hot, the input it takes
    wire [N-1:0]                 won;           // per input: its pick won at its output
    wire [N-1:0][VC_WIDTH-1:0]   free_vc;       // per output: its highest free VC with a credit
    wire [N-1:0]                 any_free;      // ... there is one
    wire [N-1:0]                 pick_need;     // per input: its pick is a head (need_vc)

    // @kb: rtl/lib/block/noc/combined_alloc
    for (genvar r = 0; r < N; r++) begin: g_credit_port
        wire [NUM_VCS-1:0] free_credit;         // its VCs free and with a credit

        for (genvar w = 0; w < NUM_VCS; w++) begin: g_credit_vc
            NocPkg::vc_out_state_t o;

            assign o            = out_vc_state[r][w];
            assign credit[r][w] = o.has_credit;
            And2 #(1) u_and2_free_credit(.in1(o.free), .in2(o.has_credit), .out(free_credit[w]));
        end
        PriorityEncoder #(.SIZE(VC_WIDTH)) u_priority_encoder_free(
            .in(VC_N'(free_credit)), .out(free_vc[r]), .valid(any_free[r]));
    end

    // Stage 1: each input port picks one of its eligible VCs.
    for (genvar p = 0; p < N; p++) begin: g_in_port
        wire [NUM_VCS-1:0]                 eligible;
        wire [NUM_VCS-1:0]                 needs;   // each VC's request is a head's
        wire [NUM_VCS-1:0][PORT_WIDTH-1:0] routes;  // the route of each VC
        // The decoder's outputs at N and above are never set (a route is a port).
        /* verilator lint_off UNUSEDSIGNAL */
        wire [PORT_N-1:0]                  want_of;
        /* verilator lint_on UNUSEDSIGNAL */

        for (genvar v = 0; v < NUM_VCS; v++) begin: g_in_vc
            // The request's vc is not read with one VC (g_one_vc: VC 0 is the only one).
            /* verilator lint_off UNUSEDSIGNAL */
            SA_REQ_T           q;               // the input VC's request
            /* verilator lint_on UNUSEDSIGNAL */
            wire [NUM_VCS-1:0] port_credit;     // the credits of its request's port
            wire               vc_credit;       // ... of its output VC
            wire               port_free;       // its port has a free VC with a credit
            wire               can_go;          // the credit it needs

            assign q         = sa_req[p][v];
            assign routes[v] = q.port;
            assign needs[v]  = q.need_vc;
            MuxN #(.N(N), .WIDTH(NUM_VCS)) u_mux_n_port_credit(
                .in(credit), .sel(q.port), .out(port_credit));
            if (NUM_VCS == 1) begin: g_one_vc
                assign vc_credit = port_credit[0];
            end else begin: g_vcs
                MuxN #(.N(NUM_VCS), .WIDTH(1)) u_mux_n_vc_credit(
                    .in(port_credit), .sel(q.vc), .out(vc_credit));
            end
            MuxN #(.N(N), .WIDTH(1)) u_mux_n_port_free(.in(any_free), .sel(q.port),
                                                       .out(port_free));
            Mux2 #(1) u_mux2_can_go(.in0(vc_credit), .in1(port_free), .sel(q.need_vc),
                                    .out(can_go));
            And2 #(1) u_and2_eligible(.in1(q.valid), .in2(can_go), .out(eligible[v]));
        end

        // One VC: it is the pick when eligible (an arbiter needs two requesters).
        if (NUM_VCS == 1) begin: g_one_vc
            assign has_pick[p]   = eligible[0];
            assign pick_vc[p]    = '0;
            assign pick_route[p] = routes[0];
            assign pick_need[p]  = needs[0];
        end else begin: g_arbiter
            wire [NUM_VCS-1:0] pick;            // one-hot, the stage-1 pick

            RoundRobinArbiter #(.N(NUM_VCS)) u_in_arbiter(
                .clk, .rst_n, .req(eligible), .advance(won[p]), .grant(pick));
            PriorityEncoder #(.SIZE(VC_WIDTH)) u_priority_encoder_pick(
                .in(VC_N'(pick)), .out(pick_vc[p]), .valid(has_pick[p]));
            MuxN #(.N(NUM_VCS), .WIDTH(PORT_WIDTH)) u_mux_n_pick_route(
                .in(routes), .sel(pick_vc[p]), .out(pick_route[p]));
            MuxN #(.N(NUM_VCS), .WIDTH(1)) u_mux_n_pick_need(
                .in(needs), .sel(pick_vc[p]), .out(pick_need[p]));
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

    // The output VC given at each output whose taken input is a head.
    for (genvar r = 0; r < N; r++) begin: g_alloc
        wire [N-1:0]    head_win;               // the taken input, when a head
        wire            gives;                  // the output gives its free VC
        // The decoder's outputs at NUM_VCS and above are never set (free_vc is a VC).
        /* verilator lint_off UNUSEDSIGNAL */
        wire [VC_N-1:0] alloc;
        /* verilator lint_on UNUSEDSIGNAL */

        And2 #(N) u_and2_head_win(.in1(win[r]), .in2(pick_need), .out(head_win));
        OrReduce #(N) u_or_reduce_gives(.in(head_win), .out(gives));
        Decoder #(.SIZE(VC_WIDTH)) u_decoder_alloc(.in(free_vc[r]), .en(gives), .out(alloc));
        assign vc_alloc[r] = alloc[NUM_VCS-1:0];
    end

    // An input sends when its pick won (at one output: the pick wants one).
    for (genvar p = 0; p < N; p++) begin: g_pop
        wire [N-1:0]        won_at;             // per output: it took this input
        VC_VLD_T            g;
        wire                head_won;           // the pick won and is a head
        wire [VC_WIDTH-1:0] grant_vc;           // the free VC of its route's port
        // The decoder's outputs at NUM_VCS and above are never set (pick_vc is a VC).
        /* verilator lint_off UNUSEDSIGNAL */
        wire [VC_N-1:0]     grant_of;
        /* verilator lint_on UNUSEDSIGNAL */

        for (genvar r = 0; r < N; r++) begin: g_won_at
            assign won_at[r] = win[r][p];
        end
        OrReduce #(N) u_or_reduce_won(.in(won_at), .out(won[p]));
        assign g.valid = won[p];
        assign g.vc    = pick_vc[p];
        assign pop[p]  = g;

        // A head that wins gets the free VC of its port.
        And2 #(1) u_and2_head_won(.in1(won[p]), .in2(pick_need[p]), .out(head_won));
        Decoder #(.SIZE(VC_WIDTH)) u_decoder_grant(.in(pick_vc[p]), .en(head_won),
                                                   .out(grant_of));
        MuxN #(.N(N), .WIDTH(VC_WIDTH)) u_mux_n_grant_vc(.in(free_vc), .sel(pick_route[p]),
                                                        .out(grant_vc));
        for (genvar v = 0; v < NUM_VCS; v++) begin: g_grant
            VC_VLD_T vg;

            assign vg.valid       = grant_of[v];
            assign vg.vc          = grant_vc;
            assign vc_grant[p][v] = vg;
        end

        `DC_ASSERT(a_wins_one_output, $onehot0(won_at))
    end

endmodule

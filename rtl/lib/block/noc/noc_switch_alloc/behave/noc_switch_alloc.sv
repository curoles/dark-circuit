/* Switch allocation of the NoC router, behavioral: which flits cross the crossbar this clock.
 *
 * An input VC may send when it asks the switch (sa_req, NocVirtChIn's: active with a flit at
 * the front) and its output VC (the request's port and vc) has a credit at the next router;
 * the allocator knows nothing of the input VCs' states. A request with need_vc (a head without
 * an output VC: combined allocation, NocPkg::ALLOC_COMBINED) may send when its port has a free
 * output VC with a credit; winning the switch, it is given that VC in the same clock, the
 * highest free one with a credit (vc_grant to the input VC, vc_alloc to the output VC, both
 * taken at the edge, as VC allocation's). An output takes one input a clock, so it gives at
 * most one VC a clock: nothing is speculative, no switch slot is wasted. This holds because
 * a head asks one port and any free VC of it may carry it (NocVirtChRouter's routing
 * assumption; kb rtl/lib/block/noc/combined_alloc). With no need_vc request the VC outputs
 * stay 0.
 *
 * At most one flit leaves an input port and at most one enters an output port per clock: a
 * separable allocator, input first. Stage 1: each input port picks one of its eligible VCs
 * (RoundRobinArbiter over its VCs); the pick wants its route.
 * Stage 2: each output port picks one of the inputs whose pick wants it (RoundRobinArbiter over
 * the inputs) and selects it in the crossbar. An output arbiter's order moves with every grant;
 * an input arbiter's only when its pick also won at the output (iSLIP): a pick that lost keeps its
 * priority and goes again, so no VC starves behind a busy output. Not maximal: a pick that loses
 * leaves its input idle even if another of its VCs wanted a free output. pop tells the input unit
 * which VC sends (its flit leaves for the crossbar); the output VC counts the flit when it shows
 * on out_fwd, in this clock (switch allocation and traversal in one clock).
 *
 *  stage 1, per input port p                       stage 2, per output port r
 *  sa_req[p][v] -------+
 *  (valid)             +--> eligible --> RoundRobinArbiter [p] --> pick, wants port r
 *  out_vc_state[r][w] -+                 (over its VCs;                |
 *  (credit of port,                       advance: pick won)           v
 *   vc)                      inputs whose pick wants r --> RoundRobinArbiter [r] --> xbar_sel[r]
 *                                                          (over the inputs)      xbar_valid[r]
 *                  pop[p] = {valid: p's pick won, vc: the pick} <----+
 *         a head's pick won: vc_grant[p][pick] = free VC of r, vc_alloc[r][that VC]
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
    logic [N*NUM_VCS-1:0]         credit;       // output VC (r, w) at r * NUM_VCS + w: a credit
    logic [N-1:0][NUM_VCS-1:0]    pick;         // per input: one-hot, its stage-1 pick
    logic [N-1:0][PORT_WIDTH-1:0] pick_route;   // per input: the output its pick wants
    logic [N-1:0][VC_WIDTH-1:0]   pick_vc;      // per input: the VC of its pick
    logic [N-1:0][N-1:0]          want;         // per output: the inputs whose pick wants it
    logic [N-1:0][N-1:0]          win;          // per output: one-hot, the input it takes
    logic [N-1:0]                 won;          // per input: its pick won at its output
    logic [N-1:0][VC_WIDTH-1:0]   free_vc;      // per output: its highest free VC with a credit
    logic [N-1:0]                 any_free;     // ... there is one
    logic [N-1:0]                 pick_need;    // per input: its pick is a head (need_vc)

    // Index of the set bit of a one-hot VC pick and of a one-hot output grant.
    function automatic logic [VC_WIDTH-1:0] vc_index(input logic [NUM_VCS-1:0] g);
        logic [VC_WIDTH-1:0] k;
        k = '0;
        for (int i = 0; i < NUM_VCS; i++)
            if (g[i])
                k = VC_WIDTH'(i);
        return k;
    endfunction

    // The highest set bit of the free VCs with a credit of a port.
    function automatic logic [VC_WIDTH-1:0] highest(input logic [NUM_VCS-1:0] free);
        logic [VC_WIDTH-1:0] h;
        h = '0;
        for (int w = 0; w < NUM_VCS; w++)
            if (free[w])
                h = VC_WIDTH'(w);
        return h;
    endfunction

    function automatic logic [PORT_WIDTH-1:0] port_index(input logic [N-1:0] g);
        logic [PORT_WIDTH-1:0] k;
        k = '0;
        for (int i = 0; i < N; i++)
            if (g[i])
                k = PORT_WIDTH'(i);
        return k;
    endfunction

    // The output VCs' credits, flat: picked by a route and a VC (signals) below; per output
    // port the free VC with a credit a head would get (from the output VCs' flops only).
    // @kb: rtl/lib/block/noc/combined_alloc
    for (genvar r = 0; r < N; r++) begin: g_credit_port
        logic [NUM_VCS-1:0] free_credit;        // its VCs free and with a credit

        for (genvar w = 0; w < NUM_VCS; w++) begin: g_credit_vc
            NocPkg::vc_out_state_t o;

            assign o                       = out_vc_state[r][w];
            assign credit[r * NUM_VCS + w] = o.has_credit;
            assign free_credit[w]          = o.free && o.has_credit;
        end
        assign free_vc[r]  = highest(free_credit);
        assign any_free[r] = |free_credit;
    end

    // Stage 1: each input port picks one of its eligible VCs.
    for (genvar p = 0; p < N; p++) begin: g_in_port
        logic [NUM_VCS-1:0]            eligible;
        logic [NUM_VCS-1:0]            needs;   // each VC's request is a head's
        logic [NUM_VCS*PORT_WIDTH-1:0] routes;  // the route of each VC

        for (genvar v = 0; v < NUM_VCS; v++) begin: g_in_vc
            SA_REQ_T q;                         // the input VC's request

            assign q = sa_req[p][v];
            assign routes[v * PORT_WIDTH +: PORT_WIDTH] = q.port;
            assign needs[v]    = q.need_vc;
            // A head: its port has a free VC with a credit; else its own VC's credit.
            assign eligible[v] = q.valid
                              && (q.need_vc ? any_free[q.port]
                                            : credit[int'(q.port) * NUM_VCS + int'(q.vc)]);
        end

        // One VC: it is the pick when eligible (an arbiter needs two requesters).
        if (NUM_VCS == 1) begin: g_one_vc
            assign pick[p] = eligible;
        end else begin: g_arbiter
            RoundRobinArbiter #(.N(NUM_VCS)) u_in_arbiter(
                .clk, .rst_n, .req(eligible), .advance(won[p]), .grant(pick[p]));
        end

        assign pick_vc[p]    = vc_index(pick[p]);
        assign pick_route[p] = routes[int'(pick_vc[p]) * PORT_WIDTH +: PORT_WIDTH];
        assign pick_need[p]  = needs[pick_vc[p]];
    end

    // Stage 2: each output port picks one of the inputs whose pick wants it.
    for (genvar r = 0; r < N; r++) begin: g_out_port
        for (genvar p = 0; p < N; p++) begin: g_want
            assign want[r][p] = |pick[p] && pick_route[p] == PORT_WIDTH'(r);
        end

        RoundRobinArbiter #(.N(N)) u_out_arbiter(
            .clk, .rst_n, .req(want[r]), .advance(1'b1), .grant(win[r]));

        assign xbar_valid[r] = |win[r];
        assign xbar_sel[r]   = port_index(win[r]);

        // The output VC given, when the input it takes is a head.
        for (genvar w = 0; w < NUM_VCS; w++) begin: g_alloc
            assign vc_alloc[r][w] = |(win[r] & pick_need) && free_vc[r] == VC_WIDTH'(w);
        end
    end

    // An input sends when its pick won (at one output: the pick wants one).
    for (genvar p = 0; p < N; p++) begin: g_pop
        logic [N-1:0] won_at;                   // per output: it took this input
        VC_VLD_T      g;

        for (genvar r = 0; r < N; r++) begin: g_won_at
            assign won_at[r] = win[r][p];
        end
        assign won[p]  = |won_at;
        assign g.valid = won[p];
        assign g.vc    = pick_vc[p];
        assign pop[p]  = g;

        // A head that wins gets the free VC of its port.
        for (genvar v = 0; v < NUM_VCS; v++) begin: g_grant
            VC_VLD_T vg;

            assign vg.valid       = won[p] && pick_need[p] && pick_vc[p] == VC_WIDTH'(v);
            assign vg.vc          = free_vc[pick_route[p]];
            assign vc_grant[p][v] = vg;
        end

        `DC_ASSERT(a_wins_one_output, $onehot0(won_at))
    end

endmodule

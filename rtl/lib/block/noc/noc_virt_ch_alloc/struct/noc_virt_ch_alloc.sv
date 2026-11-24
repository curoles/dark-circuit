/* VC allocation of the NoC router, made of blocks and gates.
 *
 * Same ports, parameters and behavior as the behave version (see there). An input VC's
 * request's port, decoded (Decoder, enabled by its valid), is its request to every output port
 * at once.
 * Per output port the free VC it gives is the highest free one (PriorityEncoder, whose valid
 * says the port has one); the vc an input VC gets is the free VC of its route's port (MuxN).
 *
 *   per input VC (p, v), requester p * NUM_VCS + v:
 *     va_req.valid --> en +---------+
 *     va_req.port ---> in  | Decoder |--> req[r][p * NUM_VCS + v], every port r
 *                          +---------+
 *     win[r][p * NUM_VCS + v], every r --> OrReduce --> vc_grant.valid
 *     free_vc[r], every r --> MuxN (sel: va_req.port) --> vc_grant.vc
 *
 *   per output port r:
 *     free of its VCs --> PriorityEncoder --> free_vc[r], any_free[r]
 *     req[r] --> And2 (any_free[r]) --> RoundRobinArbiter --> win[r] --> OrReduce --> grants[r]
 *     free_vc[r] --> Decoder (en: grants[r]) --> vc_alloc[r]
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "dark_circuit_assert.svh"
`include "../block/noc/dark_circuit_noc.svh"

module NocVirtChAlloc #(
    parameter  N          = NocPkg::MESH_PORTS, // ports: inputs and outputs
    parameter  NUM_VCS    = 2,                  // virtual channels on every link
    localparam VC_WIDTH   = `DC_NOC_VC_WIDTH(NUM_VCS),
    localparam PORT_WIDTH = `DC_NOC_PORT_WIDTH(N),
    localparam type VC_VLD_T   = `DC_NOC_VC_VLD_T(VC_WIDTH),
    localparam type VA_REQ_T   = `DC_NOC_VA_REQ_T(PORT_WIDTH)
)(
    input  wire                                        clk,
    input  wire                                        rst_n,         // synchronous, active low
    input  VA_REQ_T               [N-1:0][NUM_VCS-1:0] va_req,        // input VCs: a VC of a port
    input  NocPkg::vc_out_state_t [N-1:0][NUM_VCS-1:0] out_vc_state,  // free output VCs
    output VC_VLD_T               [N-1:0][NUM_VCS-1:0] vc_grant,      // to an input VC: its VC
    output logic                  [N-1:0][NUM_VCS-1:0] vc_alloc       // an output VC taken
);
    localparam R      = N * NUM_VCS;            // requesters: every input VC, p * NUM_VCS + v
    localparam VC_N   = 1 << VC_WIDTH;          // inputs of a VC encoder, outputs of a decoder
    localparam PORT_N = 1 << PORT_WIDTH;        // outputs of a route decoder

    wire [N-1:0][R-1:0]        req;             // per output port: the input VCs waiting for it
    wire [N-1:0][R-1:0]        win;             // per output port: one-hot, its winner
    wire [N-1:0][VC_WIDTH-1:0] free_vc;         // per output port: the free VC it gives

    for (genvar p = 0; p < N; p++) begin: g_in_port
        for (genvar v = 0; v < NUM_VCS; v++) begin: g_in_vc
            VA_REQ_T           q;               // the input VC's request
            // The decoder's outputs at N and above are never set (a route is a port).
            /* verilator lint_off UNUSEDSIGNAL */
            wire [PORT_N-1:0]  route_req;
            /* verilator lint_on UNUSEDSIGNAL */
            wire [N-1:0]       won;             // per output port: this input VC won there
            VC_VLD_T           g;

            assign q = va_req[p][v];
            Decoder #(.SIZE(PORT_WIDTH)) u_decoder_req(.in(q.port), .en(q.valid),
                                                      .out(route_req));
            for (genvar r = 0; r < N; r++) begin: g_out_port
                assign req[r][p * NUM_VCS + v] = route_req[r];
                assign won[r]                  = win[r][p * NUM_VCS + v];
            end

            // It asked one port: the VC is that port's free VC.
            OrReduce #(N) u_or_reduce_valid(.in(won), .out(g.valid));
            MuxN #(.N(N), .WIDTH(VC_WIDTH)) u_mux_n_vc(.in(free_vc), .sel(q.port), .out(g.vc));
            assign vc_grant[p][v] = g;

            `DC_ASSERT(a_wins_one_port, $onehot0(won))
        end
    end

    for (genvar r = 0; r < N; r++) begin: g_out_port
        wire [NUM_VCS-1:0] free;                // the free output VCs of this port
        wire               any_free;
        wire [R-1:0]       req_free;            // the requests, when the port has a free VC
        wire               grants;              // the port grants this clock
        // The decoder's outputs at NUM_VCS and above are never set (free_vc is a VC).
        /* verilator lint_off UNUSEDSIGNAL */
        wire [VC_N-1:0]    alloc;
        /* verilator lint_on UNUSEDSIGNAL */

        for (genvar w = 0; w < NUM_VCS; w++) begin: g_out_vc
            // The output VC's state: only free is read here (credits: switch allocation).
            /* verilator lint_off UNUSEDSIGNAL */
            NocPkg::vc_out_state_t o;
            /* verilator lint_on UNUSEDSIGNAL */

            assign o       = out_vc_state[r][w];
            assign free[w] = o.free;
        end

        PriorityEncoder #(.SIZE(VC_WIDTH)) u_priority_encoder_free(
            .in(VC_N'(free)), .out(free_vc[r]), .valid(any_free));

        // Only a port with a free VC grants; its grant is always used.
        And2 #(R) u_and2_req_free(.in1(req[r]), .in2({R{any_free}}), .out(req_free));
        RoundRobinArbiter #(.N(R)) u_arbiter(
            .clk, .rst_n, .req(req_free), .advance(1'b1), .grant(win[r]));

        OrReduce #(R) u_or_reduce_grants(.in(win[r]), .out(grants));
        Decoder #(.SIZE(VC_WIDTH)) u_decoder_alloc(.in(free_vc[r]), .en(grants), .out(alloc));
        assign vc_alloc[r] = alloc[NUM_VCS-1:0];
    end

endmodule

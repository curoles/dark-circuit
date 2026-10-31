/* Round-robin arbiter, made of blocks and gates: one of N requesters wins, the priority rotates.
 *
 * Same ports, parameter and behavior as the behave version (see there).
 *
 *   req ---+--> And2 (below_q) --> masked --+--> Mux2 --> PriorityEncoder --> Decoder --> grant
 *          |                       OrReduce |     ^ sel: a request below      (highest)    |
 *          +----------------------------------------+                                     |
 *   below_q <-- DffSyncRstEn (en: advance and a grant, reset: all) <-- bits below grant <--+
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "dark_circuit_assert.svh"

module RoundRobinArbiter #(
    parameter  N      = 4,                  // requesters, at least 2
    localparam W      = $clog2(N),          // bits of an index
    localparam N_POW2 = 1 << W              // N rounded up to a power of 2 (PriorityEncoder)
)(
    input  wire         clk,
    input  wire         rst_n,              // synchronous reset, active low
    input  wire [N-1:0] req,
    input  wire         advance,            // the grant is used: the order moves on
    output wire [N-1:0] grant               // one-hot winner, 0 when no request
);
    `DC_STATIC_ASSERT(a_n, N >= 2)

    wire [N-1:0]      below_q;              // requesters below the last winner: they come first
    wire [N-1:0]      below_next;           // those below this grant's winner
    wire [N-1:0]      masked;               // requests below the last winner
    wire              has_masked;
    wire [N-1:0]      cand;                 // the requests the winner comes from
    wire [W-1:0]      winner;               // index of the highest candidate
    wire              any;                  // a request: a grant
    wire              moves;                // the grant is used
    // The decoder's bits above N-1 are never set (winner is a requester).
    /* verilator lint_off UNUSEDSIGNAL */
    wire [N_POW2-1:0] grant_pow2;
    /* verilator lint_on UNUSEDSIGNAL */

    And2     #(N) u_and2_masked     (.in1(req), .in2(below_q), .out(masked));
    OrReduce #(N) u_or_reduce_masked(.in(masked), .out(has_masked));
    Mux2     #(N) u_mux2_cand       (.in0(req), .in1(masked), .sel(has_masked), .out(cand));

    PriorityEncoder #(.SIZE(W)) u_priority_encoder_winner(
        .in(N_POW2'(cand)), .out(winner), .valid(any));
    Decoder #(.SIZE(W)) u_decoder_grant(.in(winner), .en(any), .out(grant_pow2));
    assign grant = grant_pow2[N-1:0];

    // Bit i of the next order: the winner is above i.
    for (genvar i = 0; i < N - 1; i++) begin: g_below
        OrReduce #(N - 1 - i) u_or_reduce_above(.in(grant[N-1:i+1]), .out(below_next[i]));
    end
    assign below_next[N-1] = 1'b0;

    And2 #(1) u_and2_moves(.in1(advance), .in2(any), .out(moves));
    DffSyncRstEn #(.WIDTH(N), .RST_VAL({N{1'b1}})) u_dff_sync_rst_en_below(
        .clk, .rst_n, .en(moves), .in(below_next), .out(below_q));

endmodule

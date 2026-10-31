/* Matrix arbiter, least recently granted first, made of blocks and gates: one of N requesters
 * wins.
 *
 * Same ports, parameter and behavior as the behave version (see there): the struct AgeMatrix,
 * its order in a DffSyncRst (reset: all 0, requester 0 the least recently granted), the index
 * of the grant from a PriorityEncoder (one-hot: its only bit is its highest).
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "dark_circuit_assert.svh"

module MatrixLruArbiter #(
    parameter  N          = 4,                  // requesters, at least 2
    localparam W          = $clog2(N),          // bits of an index
    localparam N_POW2     = 1 << W,             // N rounded up to a power of 2 (PriorityEncoder)
    localparam AGES_WIDTH = N * (N - 1) / 2     // the order: a bit per pair
)(
    input  wire         clk,
    input  wire         rst_n,                  // synchronous reset, active low
    input  wire [N-1:0] req,
    input  wire         advance,                // the grant is used: the order moves on
    output wire [N-1:0] grant                   // one-hot winner, 0 when no request
);
    `DC_STATIC_ASSERT(a_n, N >= 2)

    wire [AGES_WIDTH-1:0] ages_q;
    wire [AGES_WIDTH-1:0] ages_next;
    wire [W-1:0]          winner;               // index of the grant
    wire                  any;                  // a request: a grant
    wire                  touch;                // the grant is used

    PriorityEncoder #(.SIZE(W)) u_priority_encoder_winner(
        .in(N_POW2'(grant)), .out(winner), .valid(any));
    And2 #(1) u_and2_touch(.in1(advance), .in2(any), .out(touch));

    AgeMatrix #(.SIZE(N)) u_age_matrix(
        .ages(ages_q), .touch, .touch_index(winner), .ages_next,
        .select_mask(req), .select_oldest(grant));

    DffSyncRst #(.WIDTH(AGES_WIDTH)) u_dff_sync_rst_ages(
        .clk, .rst_n, .in(ages_next), .out(ages_q));

endmodule

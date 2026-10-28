/* Credit barrier, made of blocks and gates: waits until the participants of a step have
 * reported enough work (credits), then tells the manager.
 *
 * Same ports and behavior as the behave version, see there. Instead of the sum and the
 * amount it keeps what is still missing, remaining: the amount when armed, minus each credit
 * taken. A credit reaches the amount when it is at least remaining: KoggeStoneAdder computes
 * remaining + ~credit + 1 = remaining - credit, and the release comes on a borrow (no carry
 * out) or a difference of 0 (NorReduce). One WIDTH-bit adder, no WIDTH+1-bit sum: after the
 * release no credit is taken, so the difference that wraps is never used.
 * Arming, a credit and a clear need states that exclude each other (not armed; armed and not
 * released; released), so at most one happens in a clock:
 *   armed    = DffSyncRst(take_cfg OR (armed AND NOT clear_now))
 *   released = DffSyncRst((take_cfg AND amount == 0) OR (take_credit AND reach) OR
 *                         (released AND NOT clear_now))
 *   remaining: Dff with Mux2 (take_credit: the difference; take_cfg: the amount), no reset
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module CreditBarrier #(
    parameter WIDTH = 16                        // credits and amounts
)(
    input  wire             clk,
    input  wire             rst_n,              // synchronous reset, active low: not armed

    // Arming, by the manager (or an instruction decoder)
    input  wire             cfg_valid,
    input  wire [WIDTH-1:0] cfg_waiting_amount,
    output wire             cfg_ready,          // not armed: the barrier takes an amount

    // Credits of the participants, merged outside
    input  wire             credit_valid,
    input  wire [WIDTH-1:0] credit_amount,
    output wire             credit_ready,       // armed and not released

    // Release, acknowledged by the manager
    output wire             barrier_released,
    input  wire             clear_released      // the manager saw the release: disarm
);
    wire             armed;
    wire             armed_kept;    // armed, and no clear now
    wire             armed_next;
    wire             released;
    wire             released_n;
    wire             released_kept; // released, and no clear now
    wire             released_next;
    wire             take_cfg;
    wire             take_credit;
    wire             clear_now;     // the manager clears a release
    wire             clear_n;
    wire             cfg_zero;      // the amount armed now is 0: released at once
    wire             rel_cfg;
    wire             rel_credit;
    wire [WIDTH-1:0] remaining;     // what the credits still have to bring, while armed
    wire [WIDTH-1:0] remaining_credit;
    wire [WIDTH-1:0] remaining_next;
    wire [WIDTH-1:0] credit_n;
    wire [WIDTH-1:0] diff;          // remaining - credit_amount
    wire             no_borrow;     // remaining >= credit_amount
    wire             borrow;
    wire             diff_zero;
    wire             reach;         // the credit reaches the amount: credit >= remaining

    // Handshakes.
    Inv  #(1) u_inv_armed      (.in(armed), .out(cfg_ready));
    Inv  #(1) u_inv_released   (.in(released), .out(released_n));
    And2 #(1) u_and2_credit_rdy(.in1(armed), .in2(released_n), .out(credit_ready));
    And2 #(1) u_and2_take_cfg  (.in1(cfg_valid), .in2(cfg_ready), .out(take_cfg));
    And2 #(1) u_and2_take_cred (.in1(credit_valid), .in2(credit_ready), .out(take_credit));
    And2 #(1) u_and2_clear     (.in1(released), .in2(clear_released), .out(clear_now));
    Inv  #(1) u_inv_clear      (.in(clear_now), .out(clear_n));
    assign barrier_released = released;

    // @kb: rtl/lib/block/credit_barrier/release_rule
    // A credit reaches the amount when it is at least what is still missing: a borrow of
    // remaining - credit, or a difference of 0. The release comes with that credit.
    Inv  #(WIDTH) u_inv_credit(.in(credit_amount), .out(credit_n));
    KoggeStoneAdder #(.WIDTH(WIDTH)) u_kogge_stone_adder(
        .in1(remaining), .in2(credit_n), .ci(1'b1), .co(no_borrow), .sum(diff));
    Inv       #(1)     u_inv_borrow   (.in(no_borrow), .out(borrow));
    NorReduce #(WIDTH) u_nor_reduce   (.in(diff), .out(diff_zero));
    Or2       #(1)     u_or2_reach    (.in1(borrow), .in2(diff_zero), .out(reach));
    NorReduce #(WIDTH) u_nor_reduce_cfg(.in(cfg_waiting_amount), .out(cfg_zero));

    // State (see the header for why the three events need no priority).
    And2 #(1) u_and2_armed_kept(.in1(armed), .in2(clear_n), .out(armed_kept));
    Or2  #(1) u_or2_armed      (.in1(take_cfg), .in2(armed_kept), .out(armed_next));
    DffSyncRst #(.WIDTH(1)) u_dff_sync_rst_armed(.clk, .rst_n, .in(armed_next), .out(armed));

    And2 #(1) u_and2_rel_cfg   (.in1(take_cfg), .in2(cfg_zero), .out(rel_cfg));
    And2 #(1) u_and2_rel_credit(.in1(take_credit), .in2(reach), .out(rel_credit));
    And2 #(1) u_and2_rel_kept  (.in1(released), .in2(clear_n), .out(released_kept));
    Or3  #(1) u_or3_released   (.in1(rel_cfg), .in2(rel_credit), .in3(released_kept),
                                .out(released_next));
    DffSyncRst #(.WIDTH(1)) u_dff_sync_rst_released(.clk, .rst_n, .in(released_next),
                                                    .out(released));

    // remaining means something only while armed: no reset.
    Mux2 #(WIDTH) u_mux2_credit(.in0(remaining), .in1(diff), .sel(take_credit),
                                .out(remaining_credit));
    Mux2 #(WIDTH) u_mux2_cfg   (.in0(remaining_credit), .in1(cfg_waiting_amount), .sel(take_cfg),
                                .out(remaining_next));
    Dff  #(WIDTH) u_dff_remaining(.clk, .in(remaining_next), .out(remaining));

endmodule

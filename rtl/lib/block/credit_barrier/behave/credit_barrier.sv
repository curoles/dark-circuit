/* Credit barrier, behavioral: waits until the participants of a step have reported enough
 * work (credits), then tells the manager.
 *
 * The manager arms the barrier with the amount to wait for (cfg_valid, cfg_waiting_amount,
 * taken while cfg_ready=1, that is while the barrier is not armed). Participants send
 * credits (credit_valid, credit_amount, taken while credit_ready=1); there is one port, the
 * participants are merged outside (an arbiter). When the credits taken since arming reach
 * the amount (sum >= amount), barrier_released=1 from the next clock on, and credit_ready=0
 * from then on: no credit is taken once the barrier is satisfied. What the last credit
 * brings beyond the amount is not kept. An amount of 0 releases at once (the clock after
 * arming). The manager acknowledges with clear_released while released: the barrier is not
 * armed any more (cfg_ready=1); clear_released at other times is ignored.
 * The barrier keeps what is still missing (remaining): the amount when armed, minus each
 * credit taken; a credit that is at least remaining reaches the amount. WIDTH bits are
 * enough: after the release no credit is taken, so remaining never goes below 0.
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
    logic [WIDTH-1:0] remaining;    // what the credits still have to bring, while armed
    logic             reach;        // the credit offered now reaches the amount
    logic             armed;
    logic             released;
    logic             take_cfg;
    logic             take_credit;

    assign cfg_ready        = !armed;
    assign credit_ready     = armed && !released;
    assign barrier_released = released;
    assign take_cfg         = cfg_valid && cfg_ready;
    assign take_credit      = credit_valid && credit_ready;
    assign reach            = credit_amount >= remaining;

    // @kb: rtl/lib/block/credit_barrier/release_rule
    // The release comes with the credit that reaches the amount (credit >= remaining, before
    // remaining is lowered), so credit_ready drops at once and no credit is taken after the
    // barrier is satisfied.
    always_ff @(posedge clk)
        if (!rst_n) begin
            armed    <= 1'b0;
            released <= 1'b0;
        end else if (take_cfg) begin
            armed    <= 1'b1;
            released <= cfg_waiting_amount == '0;
        end else if (take_credit) begin
            released <= reach;
        end else if (released && clear_released) begin
            armed    <= 1'b0;
            released <= 1'b0;
        end

    // remaining means something only while armed: no reset.
    always_ff @(posedge clk)
        if (take_cfg)
            remaining <= cfg_waiting_amount;
        else if (take_credit)
            remaining <= remaining - credit_amount;

endmodule

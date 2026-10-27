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
 * The sum has WIDTH+1 bits: before the last credit it is below the amount, so with the last
 * credit it is below 2 * 2^WIDTH, it never overflows.
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
    logic [WIDTH-1:0] target;       // the amount to wait for
    logic [WIDTH:0]   sum;          // credits taken since arming
    logic [WIDTH:0]   sum_next;     // with the credit taken now
    logic             armed;
    logic             released;
    logic             take_cfg;
    logic             take_credit;

    assign cfg_ready        = !armed;
    assign credit_ready     = armed && !released;
    assign barrier_released = released;
    assign take_cfg         = cfg_valid && cfg_ready;
    assign take_credit      = credit_valid && credit_ready;
    assign sum_next         = sum + {1'b0, credit_amount};

    // @kb: rtl/lib/block/credit_barrier/release_rule
    // The release comes with the credit that reaches the amount (sum_next, not sum), so
    // credit_ready drops at once and no credit is taken after the barrier is satisfied.
    always_ff @(posedge clk)
        if (!rst_n) begin
            armed    <= 1'b0;
            released <= 1'b0;
        end else if (take_cfg) begin
            armed    <= 1'b1;
            released <= cfg_waiting_amount == '0;
        end else if (take_credit) begin
            released <= sum_next >= {1'b0, target};
        end else if (released && clear_released) begin
            armed    <= 1'b0;
            released <= 1'b0;
        end

    // Amount and sum mean something only while armed: no reset.
    always_ff @(posedge clk)
        if (take_cfg) begin
            target <= cfg_waiting_amount;
            sum    <= '0;
        end else if (take_credit) begin
            sum <= sum_next;
        end

endmodule

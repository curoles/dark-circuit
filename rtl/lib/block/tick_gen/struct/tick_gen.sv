/* Tick generator: a one-clock tick every div + 1 clocks, on average; made of blocks and gates.
 *
 * Same ports, parameters and behavior as the behave version (see there). A Counter counts
 * down and loads the reload value when it is 0 or en is 0 (Or2 with Inv); zero is a
 * NorReduce of the count, tick = And2(en, zero). FRAC_BITS > 0: a RippleCarryAdder gives
 * acc + frac and its carry; the accumulator is a DffSyncRstEn enabled by tick and reset while
 * en is 0 (And2 of rst_n and en); the reload is the integer part, or Incr of it on a tick
 * with a carry (And2, Mux2).
 *
 *   div int --> Mux2(int, Incr(int), carry & tick) --> Counter (load: !en | zero, down)
 *                                                       --> NorReduce --> zero
 *   div frac + acc --> RippleCarryAdder --> carry, sum --> DffSyncRstEn acc (en: tick)
 *   tick = en & zero
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "dark_circuit_assert.svh"

module TickGen #(
    parameter  WIDTH     = 16,                      // bits of div
    parameter  FRAC_BITS = 0,                       // of them fractional: 0 an integer divider
    localparam IW        = WIDTH - FRAC_BITS,       // integer bits
    localparam CW        = (FRAC_BITS > 0) ? IW + 1 : IW    // the counter: the integer + 1
)(
    input  wire             clk,
    input  wire             rst_n,      // synchronous reset, active low
    input  wire             en,         // count; 0: no tick, restart
    input  wire [WIDTH-1:0] div,        // a tick every div + 1 clocks (fixed point)
    output wire             tick        // one clock
);
    `DC_STATIC_ASSERT(a_widths, IW >= 1 && FRAC_BITS >= 0)

    wire [CW-1:0] count;    // clocks to the next tick
    wire [CW-1:0] reload;   // what the counter loads: the integer part (+ a carry)
    wire          zero;
    wire          en_n;
    wire          load;
    // Not needed: the counter is loaded before it would borrow.
    /* verilator lint_off UNUSEDSIGNAL */
    wire          borrow;
    /* verilator lint_on UNUSEDSIGNAL */

    // @kb: rtl/lib/block/tick_gen/design
    NorReduce #(CW) u_nor_reduce_zero(.in(count), .out(zero));
    And2      #(1)  u_and2_tick(.in1(en), .in2(zero), .out(tick));
    Inv       #(1)  u_inv_en(.in(en), .out(en_n));
    Or2       #(1)  u_or2_load(.in1(en_n), .in2(zero), .out(load));
    Counter #(.WIDTH(CW)) u_counter(
        .clk, .rst_n, .load, .in(reload), .up_down(1'b0), .count_en(1'b1), .out(count),
        .co(borrow));

    if (FRAC_BITS == 0) begin: g_int
        assign reload = div;
    end else begin: g_frac
        wire [FRAC_BITS-1:0] acc;       // the fractional part of the clocks so far
        wire [FRAC_BITS-1:0] sum;       // acc + frac
        wire                 carry;     // a whole clock more in the next period
        wire                 add;       // the carry counts: a tick now
        wire                 acc_rst_n; // the accumulator clears while en is 0
        wire [CW-1:0]        int_part;  // the integer part of div, one bit wider
        wire [CW-1:0]        int_inc;   // ... + 1
        // The integer part + 1 cannot carry out (CW = IW + 1).
        /* verilator lint_off UNUSEDSIGNAL */
        wire                 inc_co;
        /* verilator lint_on UNUSEDSIGNAL */

        RippleCarryAdder #(FRAC_BITS) u_ripple_carry_adder_acc(
            .in1(acc), .in2(div[FRAC_BITS-1:0]), .ci(1'b0), .co(carry), .sum);
        And2 #(1) u_and2_acc_rst(.in1(rst_n), .in2(en), .out(acc_rst_n));
        DffSyncRstEn #(.WIDTH(FRAC_BITS)) u_dff_sync_rst_en_acc(
            .clk, .rst_n(acc_rst_n), .en(tick), .in(sum), .out(acc));
        And2 #(1) u_and2_add(.in1(tick), .in2(carry), .out(add));
        assign int_part = {1'b0, div[WIDTH-1:FRAC_BITS]};
        Incr #(.WIDTH(CW)) u_incr_reload(.in(int_part), .out(int_inc), .co(inc_co));
        Mux2 #(CW) u_mux2_reload(.in0(int_part), .in1(int_inc), .sel(add), .out(reload));
    end

    // See the behave version.
    `DC_ASSERT_NEXT(a_tick_one_clock, tick && div[WIDTH-1:FRAC_BITS] != '0, !tick)

endmodule

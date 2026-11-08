/* Tick generator: a one-clock tick every div + 1 clocks, on average; behavioral.
 *
 * A clock enable for slower logic (a UART's bits and its RX oversampling, I2C's SCL, SPI's
 * SCLK, a timer's tick), never a clock of its own: the library stays on one clock. div is a
 * fixed-point number of clocks with FRAC_BITS fractional bits (WIDTH bits in all), the
 * convention of SiFive's UART (baud = f / (div + 1)): div = 0 ticks in every clock.
 *  - FRAC_BITS = 0: an integer divider, a tick every div + 1 clocks exactly.
 *  - FRAC_BITS > 0: fractional-N. The integer part counts down; at each tick an accumulator
 *    adds the fractional part, and when it carries the next period is one clock longer. Every
 *    period is floor(div) + 1 or floor(div) + 2 clocks, their average div + 1 exactly (over
 *    2**FRAC_BITS ticks).
 * en = 0: no tick; the counter reloads the integer part and the accumulator clears, so after
 * en rises the first tick comes after floor(div) + 1 clocks (a restart). After reset the
 * counter is 0: with en = 1 the first tick is in the first clock. div is read at a reload:
 * change it with en = 0, or the new value counts from the next tick on.
 *
 *   div --int--> reload (+ carry) --> count down --> count == 0 --+--> tick (and en)
 *       --frac-> acc + frac at each tick --> carry ---^           |
 *   en = 0: reload, acc = 0 <-------------------------------------+ reload at zero
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

    logic [CW-1:0] count;   // clocks to the next tick
    logic          zero;

    // @kb: rtl/lib/block/tick_gen/design
    assign zero = count == '0;
    assign tick = en && zero;

    if (FRAC_BITS == 0) begin: g_int
        always_ff @(posedge clk)
            if (!rst_n)           count <= '0;
            else if (!en || zero) count <= div;
            else                  count <= count - 1'b1;
    end else begin: g_frac
        logic [FRAC_BITS-1:0] acc;      // the fractional part of the clocks so far
        logic [FRAC_BITS-1:0] acc_next;
        logic                 carry;    // a whole clock more in the next period
        assign {carry, acc_next} = acc + div[FRAC_BITS-1:0];

        always_ff @(posedge clk)
            if (!rst_n) begin
                count <= '0;
                acc   <= '0;
            end else if (!en) begin
                count <= CW'(div[WIDTH-1:FRAC_BITS]);
                acc   <= '0;
            end else if (zero) begin
                count <= CW'(div[WIDTH-1:FRAC_BITS]) + CW'(carry);
                acc   <= acc_next;
            end else
                count <= count - 1'b1;
    end

    // With an integer part above 0, no tick in the clock after a tick.
    `DC_ASSERT_NEXT(a_tick_one_clock, tick && div[WIDTH-1:FRAC_BITS] != '0, !tick)

endmodule

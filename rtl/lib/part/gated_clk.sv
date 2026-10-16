/**@file
 * @brief     Gated clock
 * @author    Igor Lesik
 * @copyright Igor Lesik
 *
 * Gated clock `gclk` is basically `clk` signal AND-ed with `enable` signal.
 * When `enable` is HI then `gclk` follows `clk`.
 *
 * When `enable` is LO then `gclk` by design can be HI or LO.
 *
 * Having it LO is bad, clock impulse is short and using it DFF may be unstable,
 * also if `en` has glitches then `gclk` will have it too.
 *
 * On other hand, having gclk posedge when clk is LO also is inconvenient.
 * Are there really 2 usage cases?
 *
 * It also beneficial to latch `enable` signal before AND-ing with `clk` signal.
 */
module GatedClk #(
    parameter CLK_LO_WHEN_DISABLED = 1
)(
    input  wire clk,
    input  wire enable,
    input  wire scan_enable,
    output wire gclk
);
    wire enable_in, enable_latch;

    Or2 #(1) u_or2(.in1(enable), .in2(scan_enable), .out(enable_in));

    generate
    if (CLK_LO_WHEN_DISABLED) begin: g_clk_lo
        // Latch is transparent while clk is 0, gclk = clk & enable_latch.
        wire clk_n;
        Inv   #(1) u_inv  (.in(clk), .out(clk_n));
        Latch #(1) u_latch(.in(enable_in), .enable(clk_n), .out(enable_latch));
        And2  #(1) u_and2 (.in1(clk), .in2(enable_latch), .out(gclk));
    end else begin: g_clk_hi
        // Latch is transparent while clk is 1, gclk = clk | ~enable_latch.
        Latch #(1) u_latch(.in(enable_in), .enable(clk), .out(enable_latch));
        Ind2  #(1) u_ind2 (.in1(clk), .in2(enable_latch), .out(gclk));
    end
    endgenerate

endmodule

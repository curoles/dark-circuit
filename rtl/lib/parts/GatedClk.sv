/**@file
 * @brief     Gated clock
 * @author    Igor Lesik
 * @copyright Igor Lesik
 *
 * Gated clock `gclk` is basically `clk` signal AND-ed with `enable` signal.
 * When `enable` is HI then `gclk` follows `clk`.
 * When `enable` is LO then `gclk` is HI. Having it LO is bad, clock impulse is
 * short and using it DFF may be unstable, also if `en` has glitches then `gclk`
 * will have it too).
 * It also benificial to latch `enable` signal before AND-ing with `clk` signal.
 */

module GatedClk (
    input  wire clk,
    input  wire enable,
    input  wire scan_enable,
    output wire gclk
);

    wire enable_in = enable | scan_enable;
    
    reg enable_latch;
    always @(clk or enable_in)
    begin
        if (clk)
            enable_latch <= enable_in;
    end
    
    assign gclk = clk | ~enable_latch;

endmodule: GatedClk

/* Slow JTAG to fast Memory Interface clock domain synchronization.
 *
 * Author: Igor Lesik 2021
 *
 * Toggle synchronizer is used to synchronize a pulse generating
 * in source clock domain to destination clock domain.
 * Signal `cdp_req` is a pulse because `state_capture_dr` is HIGH for 1 cycle.
 *
 * First, stretch source impulse.
 *
 * ![toggle](https://www.verilogpro.com/wp-content/uploads/2016/03/cdc_part2_pulse_2_toggle_gen_diag.png)
 *
 * ![src_toggle timing](https://www.verilogpro.com/wp-content/uploads/2016/03/cdc_part2_pulse_2_toggle_gen.png)
 *
 * Next, a circuit in the destination clock domain to convert the toggle back into a pulse.
 *
 * ![dest pulse](https://www.verilogpro.com/wp-content/uploads/2016/03/cdc_part2_toggle_2_pulse_gen_diag.png)
 *
 * ![dest timing](https://www.verilogpro.com/wp-content/uploads/2016/03/cdc_part2_toggle_2_pulse_gen_wave.png)
 *
 * References:
 *
 * - https://www.edn.com/get-those-clock-domains-in-sync/
 * - https://www.edn.com/synchronizer-techniques-for-multi-clock-domain-socs-fpgas/
 * - https://www.verilogpro.com/clock-domain-crossing-part-2/
 */
module Jtag2MemiSync (
    input  wire src_clk, // slow Source domain clock
    input  wire src_rst, // Source domain reset
    input  wire src_req, // Source domain signal to be synchronized
    input  wire dst_clk, // fast Destination domain clock
    input  wire dst_rst, // Destination domain reset
    output reg  dst_req  // Destination domain signal that follows src_req
);

    reg src_toggle;

    always_ff @(posedge src_clk)
    begin
        if (src_rst)
            src_toggle <= 1'b0;
        else if (src_req)
            src_toggle <= ~src_toggle;
    end

    // 2FF Synchronizer
    reg q1, q2;

    always_ff @(posedge dst_clk) begin
        if (dst_rst)
            q1 <= 1'b0;
        else
            q1 <= src_toggle;
    end

    always_ff @(posedge dst_clk) begin
        if (dst_rst)
            q2 <= 1'b0;
        else
            q2 <= q1;
    end

    // Convert toggle back to pulse
    reg q3;
    always_ff @(posedge dst_clk) begin
        if (dst_rst)
            q3 <= 1'b0;
        else
            q3 <= q2;
    end

    assign dst_req = q3 ^ q2;

endmodule

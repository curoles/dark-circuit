/* Test of GatedClk, both variants side by side:
 * lo - gclk is 0 when disabled (CLK_LO_WHEN_DISABLED=1),
 * hi - gclk is 1 when disabled (CLK_LO_WHEN_DISABLED=0).
 *
 * Clock is driven here, period 10: 5 low, then 5 high.
 * Stops at the first mismatch with $fatal.
 */
module TbGatedClk;
    reg  clk;
    reg  enable;
    reg  scan_enable;
    wire gclk_lo;
    wire gclk_hi;

    GatedClk #(.CLK_LO_WHEN_DISABLED(1)) u_gated_clk_lo(.clk(clk), .enable(enable), .scan_enable(scan_enable), .gclk(gclk_lo));
    GatedClk #(.CLK_LO_WHEN_DISABLED(0)) u_gated_clk_hi(.clk(clk), .enable(enable), .scan_enable(scan_enable), .gclk(gclk_hi));

    task check(input integer step, input exp_lo, input exp_hi);
        begin
            if (gclk_lo !== exp_lo)
                $fatal(1, "GatedClk lo, step %0d: clk=%b enable=%b scan_enable=%b got gclk=%b, expected %b",
                       step, clk, enable, scan_enable, gclk_lo, exp_lo);
            if (gclk_hi !== exp_hi)
                $fatal(1, "GatedClk hi, step %0d: clk=%b enable=%b scan_enable=%b got gclk=%b, expected %b",
                       step, clk, enable, scan_enable, gclk_hi, exp_hi);
        end
    endtask

    initial begin
        clk = 0; enable = 1; scan_enable = 0;

        // Variant hi knows enable only after its latch saw clk=1, check it from step 1.
        #2; if (gclk_lo !== 1'b0) $fatal(1, "GatedClk lo, step 0: got gclk=%b, expected 0", gclk_lo);

        // Enabled: both gated clocks follow clk.
        #3 clk = 1; #2 check(1, 1, 1);
        #3 clk = 0; #2 check(2, 0, 0);

        // Disable while clk=0: hi must not go 1 before clk rises.
        enable = 0; #1 check(3, 0, 0);
        #2 clk = 1; #2 check(4, 0, 1);
        #3 clk = 0; #2 check(5, 0, 1);

        // Enable while clk=1: lo must not make partial pulse, it starts next clk=1.
        #3 clk = 1; #1 enable = 1; #1 check(6, 0, 1);
        #3 clk = 0; #2 check(7, 0, 0);
        #3 clk = 1; #1 check(8, 1, 1);

        // Disable while clk=1: lo pulse must not be cut.
        #1 enable = 0; #1 check(9, 1, 1);
        #2 clk = 0; #2 check(10, 0, 1);
        #3 clk = 1; #2 check(11, 0, 1);

        // Enable while clk=0: hi must stay 1 until clk rises.
        #3 clk = 0; #1 enable = 1; #1 check(12, 0, 1);
        #3 clk = 1; #2 check(13, 1, 1);
        #3 clk = 0; #2 check(14, 0, 0);

        // scan_enable enables gated clocks when enable=0.
        enable = 0; scan_enable = 1; #1 check(15, 0, 0);
        #2 clk = 1; #2 check(16, 1, 1);
        #3 clk = 0; #2 check(17, 0, 0);

        $display("PASS");
        $finish;
    end
endmodule

/* Test of simulation clock and reset generators.
 *
 * Stops at the first mismatch with $fatal.
 */
module TbSim;
    localparam HALF_PERIOD = 3;
    localparam CYCLES = 4;

    wire clk;
    wire rst_n;
    integer i;

    SimClkGen #(.HALF_PERIOD(HALF_PERIOD)) u_clk_gen(.clk(clk));
    SimRstGen #(.CYCLES(CYCLES))           u_rst_gen(.clk(clk), .rst_n(rst_n));

    initial begin
        #1;
        if (clk !== 1'b0)   $fatal(1, "SimClkGen: clk=%b at start, expected 0", clk);
        if (rst_n !== 1'b0) $fatal(1, "SimRstGen: rst_n=%b at start, expected 0", rst_n);

        // Rising edges come at HALF_PERIOD, 3*HALF_PERIOD, 5*HALF_PERIOD, ...;
        // rst_n seen at an edge is 0 for the first CYCLES edges, then 1.
        for (i = 1; i <= CYCLES + 3; i = i + 1) begin
            @(posedge clk);
            if ($time != (2 * i - 1) * HALF_PERIOD)
                $fatal(1, "SimClkGen: rising edge %0d at time %0t, expected %0d", i, $time, (2 * i - 1) * HALF_PERIOD);
            if (rst_n !== (i > CYCLES))
                $fatal(1, "SimRstGen: rst_n=%b at rising edge %0d, expected %b", rst_n, i, i > CYCLES);
        end

        $display("PASS");
        $finish;
    end
endmodule

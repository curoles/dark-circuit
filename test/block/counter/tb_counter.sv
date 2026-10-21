/* Test of Counter block, behave or struct version.
 *
 * Inputs change on falling edge, after every rising edge
 * {co, out} is compared with reference model.
 * Stops at the first mismatch with $fatal.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module TbCounter;
    localparam W = 8;
    localparam [W:0] ONE = {{W{1'b0}}, 1'b1};

    wire         clk;
    reg          rst_n;
    reg          load;
    reg  [W-1:0] in;
    reg          up_down;
    reg          count_en;
    wire [W-1:0] out;
    wire         co;

    reg  [W:0]   exp;  // expected {co, out}
    // Random word, only some of its bits are used.
    /* verilator lint_off UNUSEDSIGNAL */
    reg  [31:0]  r;
    /* verilator lint_on UNUSEDSIGNAL */
    integer i;
    integer seed;

    SimClkGen #(.HALF_PERIOD(5)) u_sim_clk_gen(.clk(clk));

    Counter #(.WIDTH(W)) u_counter(.clk(clk), .rst_n(rst_n), .load(load), .in(in),
                                   .up_down(up_down), .count_en(count_en), .out(out), .co(co));

    // One clock cycle: set inputs after falling edge, check after rising edge.
    task cycle(input integer step, input r_n, input ld, input [W-1:0] value, input up, input en);
        begin
            @(negedge clk);
            rst_n = r_n; load = ld; in = value; up_down = up; count_en = en;
            @(posedge clk);
            if (!r_n)    exp = {(W+1){1'b0}};
            else if (ld) exp = {1'b0, value};
            else if (en) exp = up ? {1'b0, exp[W-1:0]} + ONE : {1'b0, exp[W-1:0]} - ONE;
            #1;
            if ({co, out} !== exp)
                $fatal(1, "Counter step %0d: rst_n=%b load=%b in=%0d up_down=%b count_en=%b got co=%b out=%0d, expected co=%b out=%0d",
                       step, r_n, ld, value, up, en, co, out, exp[W], exp[W-1:0]);
        end
    endtask

    initial begin
        rst_n = 1; load = 0; in = 0; up_down = 1; count_en = 0;
        exp = {(W+1){1'b0}};

        // Counter is unknown until reset.
        cycle(1, 0, 0, 0, 1, 1);

        // Load 250 and count up across 255 -> 0, co=1 exactly on the wrap.
        cycle(2, 1, 1, 8'd250, 1, 1);
        for (i = 0; i < 6; i = i + 1)
            cycle(10 + i, 1, 0, 0, 1, 1);
        if ({co, out} !== {1'b1, 8'd0}) $fatal(1, "Counter: 250 + 6 got co=%b out=%0d, expected co=1 out=0", co, out);
        cycle(16, 1, 0, 0, 1, 1);
        if ({co, out} !== {1'b0, 8'd1}) $fatal(1, "Counter: after wrap got co=%b out=%0d, expected co=0 out=1", co, out);

        // Load 3 and count down across 0 -> 255, co=1 (borrow) exactly there.
        cycle(20, 1, 1, 8'd3, 0, 1);
        for (i = 0; i < 4; i = i + 1)
            cycle(21 + i, 1, 0, 0, 0, 1);
        if ({co, out} !== {1'b1, 8'd255}) $fatal(1, "Counter: 3 - 4 got co=%b out=%0d, expected co=1 out=255", co, out);

        // count_en=0 holds value and co.
        for (i = 0; i < 3; i = i + 1)
            cycle(30 + i, 1, 0, 8'd99, 1, 0);

        // Reset beats load, load beats counting.
        cycle(40, 0, 1, 8'd55, 1, 1);
        cycle(41, 1, 1, 8'd77, 1, 1);

        // Random inputs, reset and load are rare to have long counting.
        seed = 1;
        for (i = 0; i < 1000; i = i + 1) begin
            r = $random(seed);
            cycle(100 + i, r[3:0] != 0, r[7:4] == 0, r[W+15:16], r[8], r[9] | r[10]);
        end

        $display("PASS");
        $finish;
    end
endmodule

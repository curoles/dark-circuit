/* Test of Lfsr, behave or struct version.
 *
 * For WIDTH 4, 8, 12 and 16: after reset q is all ones, q is never 0, and q is
 * all ones again after exactly 2^WIDTH - 1 clocks (maximal period).
 * Stops at the first mismatch with $fatal.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module TbLfsrPeriod #(
    parameter WIDTH = 4
)(
    input  wire clk,
    input  wire rst_n,
    output reg  done
);
    localparam [WIDTH-1:0] SEED = {WIDTH{1'b1}};

    wire [WIDTH-1:0] q;
    integer          n;
    reg              back;  // q is SEED again

    Lfsr #(.WIDTH(WIDTH)) u_lfsr(.clk(clk), .rst_n(rst_n), .q(q));

    initial begin
        done = 0;
        @(posedge rst_n);
        @(negedge clk);
        if (q !== SEED)
            $fatal(1, "Lfsr %0d: after reset got %h, expected %h", WIDTH, q, SEED);
        n    = 0;
        back = 0;
        while (!back) begin
            @(negedge clk);
            n = n + 1;
            if (q === {WIDTH{1'b0}})
                $fatal(1, "Lfsr %0d: zero state after %0d clocks", WIDTH, n);
            if (q === SEED || n == (1 << WIDTH))
                back = 1;
        end
        if (n != (1 << WIDTH) - 1)
            $fatal(1, "Lfsr %0d: period %0d, expected %0d", WIDTH, n, (1 << WIDTH) - 1);
        done = 1;
    end
endmodule

module TbLfsr;
    wire clk;
    wire rst_n;
    wire done4;
    wire done8;
    wire done12;
    wire done16;

    SimClkGen #(.HALF_PERIOD(5)) u_sim_clk_gen(.clk(clk));
    SimRstGen #(.CYCLES(2))      u_sim_rst_gen(.clk(clk), .rst_n(rst_n));

    TbLfsrPeriod #(.WIDTH(4))  u_tb_lfsr_period_4 (.clk(clk), .rst_n(rst_n), .done(done4));
    TbLfsrPeriod #(.WIDTH(8))  u_tb_lfsr_period_8 (.clk(clk), .rst_n(rst_n), .done(done8));
    TbLfsrPeriod #(.WIDTH(12)) u_tb_lfsr_period_12(.clk(clk), .rst_n(rst_n), .done(done12));
    TbLfsrPeriod #(.WIDTH(16)) u_tb_lfsr_period_16(.clk(clk), .rst_n(rst_n), .done(done16));

    initial begin
        wait (done4 && done8 && done12 && done16);
        $display("PASS");
        $finish;
    end
endmodule

/* Test of SignalClockSync in three configurations, each with its own two clocks of unrelated
 * periods: clk2 faster than clk1 (1 bit, 2 stages), clk2 slower (4 bits, 3 stages), and
 * without the source flop (1 bit, 2 stages). in is a flop of clk1's domain (it changes at
 * rising edges of clk1, by a nonblocking assignment, as a flop's output does), at random:
 * sometimes several clocks in a row, sometimes held long.
 *
 * Two checks, before every rising edge of clk2 (at its falling edge, which never meets an
 * edge of clk1 here: odd half periods of clk1 against even times): model, out is exactly the
 * value that crossed STAGES edges of clk2 before (a model of the chain: the value in had at
 * the last edge of clk1, or in itself without the source flop, shifted on clk2); latency, once
 * in has been stable for the latency bound (a period of clk1 with the source flop and
 * STAGES + 1 periods of clk2), out equals in. A simulation has no metastability: the chain's
 * length, its clocks and the source flop are what is checked. In the end every configuration
 * must have seen changes of in, settled values, and rising edges of both clocks at the same
 * time. Checks named with DC_TEST_FAIL (model, latency, coverage); stops at the first
 * mismatch. Mutants: kb test/part/signal_clock_sync/mutants.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
`include "dark_circuit_test.svh"

module TbSignalClockSyncCheck #(
    parameter WIDTH    = 1,
    parameter STAGES   = 2,
    parameter SRC_FLOP = 1,
    parameter HALF1    = 5,         // half periods of clk1 (odd) and clk2
    parameter HALF2    = 3,
    parameter N_CLK1   = 3000,      // clocks of clk1
    parameter SEED     = 1
)(
    output logic done
);
    localparam BOUND = (SRC_FLOP ? 2 * HALF1 : 0) + (STAGES + 1) * 2 * HALF2;

    wire                          clk1;
    wire                          clk2;
    logic [WIDTH-1:0]             in;
    wire  [WIDTH-1:0]             out;
    logic [WIDTH-1:0]             src;      // model: the source flop
    logic [STAGES-1:0][WIDTH-1:0] q;        // model: the chain on clk2
    integer                       seed;
    integer                       n_clk2;   // rising edges of clk2 so far
    integer                       n_change;
    integer                       n_settled;
    integer                       n_same_edge;
    time                          t_change; // when in changed last
    time                          t_clk1;   // the last rising edges
    time                          t_clk2;

    SimClkGen #(.HALF_PERIOD(HALF1)) u_clk1(.clk(clk1));
    SimClkGen #(.HALF_PERIOD(HALF2)) u_clk2(.clk(clk2));

    SignalClockSync #(.WIDTH(WIDTH), .STAGES(STAGES), .SRC_FLOP(SRC_FLOP)) u_signal_clock_sync(
        .clk1, .clk2, .in, .out);

    // The model, on the same edges as the part.
    always @(posedge clk1)
        src <= in;
    always @(posedge clk2)
        q <= {q[STAGES-2:0], SRC_FLOP ? src : in};

    // Loops in initial, not always @(posedge ...): blocking assignments of a testbench.
    initial begin
        t_clk1      = 0;
        t_clk2      = 1;
        n_clk2      = 0;
        n_same_edge = 0;
        fork
            forever begin
                @(posedge clk1);
                t_clk1 = $time;
                if (t_clk1 == t_clk2)
                    n_same_edge = n_same_edge + 1;
            end
            forever begin
                @(posedge clk2);
                t_clk2 = $time;
                n_clk2 = n_clk2 + 1;
                if (t_clk1 == t_clk2)
                    n_same_edge = n_same_edge + 1;
            end
        join
    end

    // The checks, at the falling edge of clk2: out settled, the next edge not yet.
    initial begin
        n_settled = 0;
        forever begin
            @(negedge clk2);
            if (n_clk2 > STAGES + 1 && out !== q[STAGES-1])
                `DC_TEST_FAIL(model, $sformatf(
                    "WIDTH %0d STAGES %0d SRC_FLOP %0d: out %h, expected %h", WIDTH, STAGES,
                    SRC_FLOP, out, q[STAGES-1]))
            if (n_clk2 > STAGES + 1 && $time - t_change > BOUND) begin
                n_settled = n_settled + 1;
                if (out !== in)
                    `DC_TEST_FAIL(latency, $sformatf(
                        "WIDTH %0d STAGES %0d SRC_FLOP %0d: in %h stable for %0t, out %h",
                        WIDTH, STAGES, SRC_FLOP, in, $time - t_change, out))
            end
        end
    end

    // in, a flop of clk1's domain: in runs of changes, or held for a while.
    initial begin
        done     = 1'b0;
        seed     = SEED;
        n_change = 0;
        in       = '0;
        t_change = 0;
        for (int k = 0; k < N_CLK1; k++) begin
            @(posedge clk1);
            if ((k / 50) % 2 == 0 ? $random(seed) % 2 == 0 : $random(seed) % 23 == 0) begin
                in       <= WIDTH'($random(seed));
                t_change = $time;
                n_change = n_change + 1;
            end
        end
        if (n_change == 0 || n_settled == 0 || n_same_edge == 0)
            `DC_TEST_FAIL(coverage, $sformatf(
                "WIDTH %0d STAGES %0d SRC_FLOP %0d: changes %0d, settled %0d, same edges %0d",
                WIDTH, STAGES, SRC_FLOP, n_change, n_settled, n_same_edge))
        done = 1'b1;
    end
endmodule

module TbSignalClockSync;
    wire done_fast;
    wire done_slow;
    wire done_wire;

    TbSignalClockSyncCheck #(.WIDTH(1), .STAGES(2), .SRC_FLOP(1), .HALF1(5), .HALF2(3),
                             .SEED(1)) u_fast(.done(done_fast));
    TbSignalClockSyncCheck #(.WIDTH(4), .STAGES(3), .SRC_FLOP(1), .HALF1(5), .HALF2(13),
                             .SEED(2)) u_slow(.done(done_slow));
    TbSignalClockSyncCheck #(.WIDTH(1), .STAGES(2), .SRC_FLOP(0), .HALF1(7), .HALF2(5),
                             .SEED(3)) u_wire(.done(done_wire));
    `DC_TEST_MUTANT_HOOK(top)

    initial begin
        wait (done_fast && done_slow && done_wire);
        $display("PASS");
        $finish;
    end
endmodule

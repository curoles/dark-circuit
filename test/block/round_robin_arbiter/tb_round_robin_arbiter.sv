/* Test of RoundRobinArbiter, behave or struct version.
 *
 * Random requests every clock, the grant used (advance) in most clocks. The model keeps the
 * index of the last winner (N after reset): the grant is the highest requester below it, else
 * the highest requester; a used grant makes its winner the last. Checked before every rising
 * edge. Every case must happen: every requester granted, a grant not used (the same requests
 * keep their grant), a grant from above the last winner (the wrap), no request. N 2, 3, 5 and 8;
 * Verilator 20000 clocks, Icarus 2000. Stops at the first mismatch with $fatal.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module TbRoundRobinArbiterCheck #(
    parameter N = 4
)(
    input  wire  clk,
    output logic done
);
`ifdef VERILATOR
    localparam N_CLOCKS = 20000;
`else
    localparam N_CLOCKS = 2000;
`endif

    logic         rst_n;
    logic [N-1:0] req;
    logic         advance;
    wire  [N-1:0] grant;

    RoundRobinArbiter #(.N(N)) u_arbiter(.clk, .rst_n, .req, .advance, .grant);

    integer last;               // the last winner, N after reset
    integer seed;
    integer n_won [N];
    integer n_held;             // a grant not used
    integer n_wrap;             // a grant from above the last winner
    integer n_none;             // no request

    // The model's winner: the highest requester below last, else the highest; -1 if none.
    function automatic integer winner(input logic [N-1:0] r);
        for (int i = last - 1; i >= 0; i--)
            if (r[i]) return i;
        for (int i = N - 1; i >= last; i--)
            if (r[i]) return i;
        return -1;
    endfunction

    initial begin
        integer w;
        done   = 1'b0;
        seed   = N * 3;
        last   = N;
        n_held = 0;
        n_wrap = 0;
        n_none = 0;
        for (int i = 0; i < N; i++)
            n_won[i] = 0;
        rst_n   = 1'b0;
        req     = '0;
        advance = 1'b0;
        @(negedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        for (int k = 0; k < N_CLOCKS; k++) begin
            req     = N'($random(seed));
            advance = {$random(seed)} % 10 < 7;
            #1;
            w = winner(req);
            if (grant !== (w < 0 ? '0 : N'(1) << w))
                $fatal(1, "RoundRobinArbiter %0d: req %b last %0d: grant %b, expected winner %0d",
                       N, req, last, grant, w);
            if (w < 0)
                n_none = n_none + 1;
            else begin
                n_won[w] = n_won[w] + 1;
                if (w >= last) n_wrap = n_wrap + 1;
                if (advance) last = w;
                else         n_held = n_held + 1;
            end
            @(negedge clk);
        end
        for (int i = 0; i < N; i++)
            if (n_won[i] == 0)
                $fatal(1, "RoundRobinArbiter %0d: requester %0d never won", N, i);
        if (n_held == 0 || n_wrap == 0 || n_none == 0)
            $fatal(1, "RoundRobinArbiter %0d: cases: held %0d, wrap %0d, none %0d", N, n_held,
                   n_wrap, n_none);
        done = 1'b1;
    end
endmodule

module TbRoundRobinArbiter;
    wire clk;
    wire done_2;
    wire done_3;
    wire done_5;
    wire done_8;

    SimClkGen #(.HALF_PERIOD(5)) u_sim_clk_gen(.clk);

    TbRoundRobinArbiterCheck #(.N(2)) u_check_2(.clk, .done(done_2));
    TbRoundRobinArbiterCheck #(.N(3)) u_check_3(.clk, .done(done_3));
    TbRoundRobinArbiterCheck #(.N(5)) u_check_5(.clk, .done(done_5));
    TbRoundRobinArbiterCheck #(.N(8)) u_check_8(.clk, .done(done_8));

    initial begin
        wait (done_2 && done_3 && done_5 && done_8);
        $display("PASS");
        $finish;
    end
endmodule

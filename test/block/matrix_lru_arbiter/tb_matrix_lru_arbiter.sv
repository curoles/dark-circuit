/* Test of MatrixLruArbiter, behave or struct version, and a fairness comparison with
 * RoundRobinArbiter.
 *
 * Check: random requests every clock, the grant used (advance) in most clocks. The model keeps
 * the clock each requester last won (after reset requester i at i - N: 0 the least recent): the
 * grant is the requester that won longest ago; a used grant makes its winner the most recent.
 * Every case must happen: every requester granted, a grant not used, two or more requesters.
 * N 2, 3, 5 and 8.
 * Fairness: both arbiters, N 5, the same arrivals: a requester without a request gets a new one
 * with probability LOAD %, keeps it until granted, and every grant is used. Each must grant a
 * request within N - 1 grants of others; the longest and the mean wait in clocks of both are
 * printed (a light load and a heavy one).
 * Verilator 20000 clocks, Icarus 2000. Stops at the first mismatch with $fatal.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module TbMatrixLruArbiterCheck #(
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

    MatrixLruArbiter #(.N(N)) u_arbiter(.clk, .rst_n, .req, .advance, .grant);

    integer won_at [N];         // the clock each requester last won
    integer seed;
    integer n_won [N];
    integer n_held;             // a grant not used
    integer n_contend;          // two or more requesters

    // The model's winner: the requester that won longest ago; -1 if none.
    function automatic integer winner(input logic [N-1:0] r);
        integer w;
        w = -1;
        for (int i = 0; i < N; i++)
            if (r[i] && (w < 0 || won_at[i] < won_at[w]))
                w = i;
        return w;
    endfunction

    initial begin
        integer w;
        done      = 1'b0;
        seed      = N * 5;
        n_held    = 0;
        n_contend = 0;
        for (int i = 0; i < N; i++) begin
            won_at[i] = i - N;
            n_won[i]  = 0;
        end
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
                $fatal(1, "MatrixLruArbiter %0d: req %b: grant %b, expected winner %0d", N, req,
                       grant, w);
            if ($countones(req) > 1)
                n_contend = n_contend + 1;
            if (w >= 0) begin
                n_won[w] = n_won[w] + 1;
                if (advance) won_at[w] = k;
                else         n_held    = n_held + 1;
            end
            @(negedge clk);
        end
        for (int i = 0; i < N; i++)
            if (n_won[i] == 0)
                $fatal(1, "MatrixLruArbiter %0d: requester %0d never won", N, i);
        if (n_held == 0 || n_contend == 0)
            $fatal(1, "MatrixLruArbiter %0d: cases: held %0d, contention %0d", N, n_held,
                   n_contend);
        done = 1'b1;
    end
endmodule

// One arbiter on the arrivals of TbArbiterFairness: its pending requests, its waits. A
// requester must be granted within N - 1 grants of others; at stop the longest and the mean
// wait are printed.
module TbArbiterWaits #(
    parameter N    = 5,
    parameter LRU  = 0,         // 1: MatrixLruArbiter, 0: RoundRobinArbiter
    parameter LOAD = 30         // for the printed line
)(
    input  wire         clk,
    input  wire         rst_n,
    input  wire [N-1:0] arrive, // new requests of this clock (where a requester has none)
    input  wire         stop    // print
);
    logic   [N-1:0] req;        // pending requests
    wire    [N-1:0] grant;
    logic   [N-1:0] granted;    // the grant of the clock before: its request is served
    integer         since  [N]; // the clock each request came
    integer         others [N]; // grants to others since then
    integer         longest;    // the longest wait, clocks
    integer         sum;        // the sum of the waits
    integer         grants;
    integer         k;          // clock

    if (LRU) begin: g_lru
        MatrixLruArbiter  #(.N(N)) u_arbiter(.clk, .rst_n, .req, .advance(1'b1), .grant);
    end else begin: g_round_robin
        RoundRobinArbiter #(.N(N)) u_arbiter(.clk, .rst_n, .req, .advance(1'b1), .grant);
    end

    initial begin
        req     = '0;
        granted = '0;
        longest = 0;
        sum     = 0;
        grants  = 0;
        k       = 0;
        forever begin
            @(negedge clk);
            #1;                     // after TbArbiterFairness drives arrive
            if (rst_n) begin
                // The request granted at the edge before is served; new ones come.
                req = req & ~granted;
                for (int r = 0; r < N; r++)
                    if (arrive[r] && !req[r]) begin
                        req[r]    = 1'b1;
                        since[r]  = k;
                        others[r] = 0;
                    end
                #1;
                for (int r = 0; r < N; r++)
                    if (grant[r]) begin
                        if (others[r] > N - 1)
                            $fatal(1, "Arbiter (LRU %0d) N %0d load %0d: requester %0d waited %0d grants",
                                   LRU, N, LOAD, r, others[r]);
                        if (k - since[r] > longest) longest = k - since[r];
                        sum    = sum + k - since[r];
                        grants = grants + 1;
                    end else if (|grant)
                        others[r] = others[r] + 1;
                granted = grant;
                k       = k + 1;
            end
        end
    end

    always @(posedge stop)
        if (LRU)
            $display("Fairness N %0d load %0d %%: MatrixLruArbiter  wait max %0d mean %0.2f clocks",
                     N, LOAD, longest, real'(sum) / grants);
        else
            $display("Fairness N %0d load %0d %%: RoundRobinArbiter wait max %0d mean %0.2f clocks",
                     N, LOAD, longest, real'(sum) / grants);
endmodule

// Fairness of both arbiters on the same arrivals: a requester without a request gets a new one
// with probability LOAD %, keeps it until granted, every grant is used.
module TbArbiterFairness #(
    parameter N    = 5,
    parameter LOAD = 30
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
    logic [N-1:0] arrive;
    logic         stop;
    integer       seed;

    TbArbiterWaits #(.N(N), .LRU(0), .LOAD(LOAD)) u_round_robin(.clk, .rst_n, .arrive, .stop);
    TbArbiterWaits #(.N(N), .LRU(1), .LOAD(LOAD)) u_matrix_lru (.clk, .rst_n, .arrive, .stop);

    initial begin
        done   = 1'b0;
        stop   = 1'b0;
        seed   = N * 7 + LOAD;
        rst_n  = 1'b0;
        arrive = '0;
        @(negedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        for (int k = 0; k < N_CLOCKS; k++) begin
            for (int r = 0; r < N; r++)
                arrive[r] = {$random(seed)} % 100 < LOAD;
            @(negedge clk);
        end
        stop = 1'b1;
        #1;
        done = 1'b1;
    end
endmodule

module TbMatrixLruArbiter;
    wire clk;
    wire done_2;
    wire done_3;
    wire done_5;
    wire done_8;
    wire done_light;
    wire done_heavy;

    SimClkGen #(.HALF_PERIOD(5)) u_sim_clk_gen(.clk);

    TbMatrixLruArbiterCheck #(.N(2)) u_check_2(.clk, .done(done_2));
    TbMatrixLruArbiterCheck #(.N(3)) u_check_3(.clk, .done(done_3));
    TbMatrixLruArbiterCheck #(.N(5)) u_check_5(.clk, .done(done_5));
    TbMatrixLruArbiterCheck #(.N(8)) u_check_8(.clk, .done(done_8));
    TbArbiterFairness #(.N(5), .LOAD(15)) u_fair_light(.clk, .done(done_light));
    TbArbiterFairness #(.N(5), .LOAD(60)) u_fair_heavy(.clk, .done(done_heavy));

    initial begin
        wait (done_2 && done_3 && done_5 && done_8 && done_light && done_heavy);
        $display("PASS");
        $finish;
    end
endmodule

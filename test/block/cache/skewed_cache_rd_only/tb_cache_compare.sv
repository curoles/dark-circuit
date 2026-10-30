/* Miss rates of two caches of 128 lines on synthetic line-address streams, models only: the
 * decision for SkewedCacheRdOnly against SetAssocCacheRdOnly.
 *
 * The skewed model is the one of the test of SkewedCacheRdOnly (2 x 64 lines, index f0 = set,
 * f1 = set ^ the low bits of the tag, a recent bit per line); the set-associative one has 64
 * sets of 2 ways with exact LRU. Both see the same streams: random over contiguous lines,
 * lines of one set cycled (conflict), strides (a matrix column), sequential loops, a loop with
 * random accesses, and working sets at scattered random addresses. It prints the miss rates
 * after a warm-up, and stops with $fatal when the skewed cache misses more than the
 * set-associative one where conflicts decide (conflict, stride 32 and 64, scattered working
 * sets, these in total): the measurement the decision rests on. 20000 accesses per stream on
 * Verilator, 1500 on Icarus.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module TbCacheCompare;
`ifdef VERILATOR
    localparam N_ACCESSES = 20000;
    localparam N_WARM     = 2000;
`else
    localparam N_ACCESSES = 1500;   // about 1 s at most for a library test
    localparam N_WARM     = 200;
`endif
    localparam SW   = 6;            // index bits: 64 lines per way, 64 sets
    localparam SETS = 1 << SW;

    typedef logic [31:0] line_t;    // a line address

    // Skewed model.
    bit     s_valid  [2][SETS];
    line_t  s_line   [2][SETS];
    bit     s_recent [2][SETS];
    // Set-associative model: per set two ways, lru: the way used longest ago.
    bit     a_valid  [SETS][2];
    line_t  a_line   [SETS][2];
    bit     a_lru    [SETS];

    line_t  scattered [128];        // a working set at random line addresses
    integer seed;

    // The index of line l in way w of the skewed cache (the higher bits do not matter).
    /* verilator lint_off UNUSEDSIGNAL */
    function automatic logic [SW-1:0] s_index(input integer w, input line_t l);
        return (w == 0) ? l[SW-1:0] : l[SW-1:0] ^ l[2*SW-1:SW];
    endfunction

    function automatic logic [SW-1:0] a_set(input line_t l);
        return l[SW-1:0];
    endfunction
    /* verilator lint_on UNUSEDSIGNAL */

    // One access to the skewed model: 1 on a miss.
    function automatic bit s_access(input line_t l);
        logic [SW-1:0] i0;
        logic [SW-1:0] i1;
        bit            v;
        i0 = s_index(0, l);
        i1 = s_index(1, l);
        if ((s_valid[0][i0] && s_line[0][i0] == l) || (s_valid[1][i1] && s_line[1][i1] == l)) begin
            v = !(s_valid[0][i0] && s_line[0][i0] == l);    // the way that hits
            s_recent[0][i0] = !v;
            s_recent[1][i1] = v;
            return 1'b0;
        end
        if (!s_valid[1][i1])                         v = 1'b1;
        else if (!s_valid[0][i0])                    v = 1'b0;
        else if (s_recent[0][i0] != s_recent[1][i1]) v = s_recent[0][i0];
        else                                         v = 1'b0;
        if (v) begin s_valid[1][i1] = 1'b1; s_line[1][i1] = l; end
        else   begin s_valid[0][i0] = 1'b1; s_line[0][i0] = l; end
        s_recent[0][i0] = !v;
        s_recent[1][i1] = v;
        return 1'b1;
    endfunction

    // One access to the set-associative model: 1 on a miss.
    function automatic bit a_access(input line_t l);
        logic [SW-1:0] s;
        bit            v;
        s = a_set(l);
        for (int w = 0; w < 2; w++)
            if (a_valid[s][w] && a_line[s][w] == l) begin
                a_lru[s] = (w == 0);    // the other way is now the older
                return 1'b0;
            end
        v = !a_valid[s][1] ? 1'b1 : !a_valid[s][0] ? 1'b0 : a_lru[s];
        a_valid[s][v] = 1'b1;
        a_line[s][v]  = l;
        a_lru[s]      = !v;
        return 1'b1;
    endfunction

    task automatic clear;
        for (int i = 0; i < SETS; i++)
            for (int w = 0; w < 2; w++) begin
                s_valid[w][i]  = 1'b0;
                s_recent[w][i] = 1'b0;
                a_valid[i][w]  = 1'b0;
            end
        for (int i = 0; i < SETS; i++)
            a_lru[i] = 1'b0;
    endtask

    // Streams: 0 random over p contiguous lines; 1 p lines of one set, cycled; 2 stride of p
    // lines, 64 elements, cycled; 3 a loop of p sequential lines; 4 70 % a loop of 80 lines and
    // 30 % random over 1024 lines; 5 random over the first p lines of scattered.
    function automatic line_t next_line(input integer kind, input integer p, input integer k);
        line_t base;
        base = 32'h0010_0000;
        case (kind)
            0: return base + line_t'($unsigned($random(seed)) % p);
            1: return base + line_t'((k % p) * SETS + 5);
            2: return base + line_t'((k % 64) * p);
            3: return base + line_t'(k % p);
            4: return ($unsigned($random(seed)) % 10 < 7) ? base + line_t'(k % 80) :
                       base + 32'h0004_0000 + line_t'($unsigned($random(seed)) % 1024);
            default: return scattered[$unsigned($random(seed)) % p];
        endcase
    endfunction

    // Run one stream on both models, print the miss rates and return the misses; with must_win
    // the skewed cache may not miss more.
    task automatic run(input string name, input integer kind, input integer p, input bit must_win,
                       output integer ms, output integer ma);
        line_t  l;
        ms = 0;
        ma = 0;
        clear();
        for (int k = 0; k < N_ACCESSES; k++) begin
            l = next_line(kind, p, k);
            if (s_access(l) && k >= N_WARM) ms = ms + 1;
            if (a_access(l) && k >= N_WARM) ma = ma + 1;
        end
        $display("%-34s skewed %6.2f %%   set-assoc %6.2f %%", name,
                 100.0 * ms / (N_ACCESSES - N_WARM), 100.0 * ma / (N_ACCESSES - N_WARM));
        // @kb: rtl/lib/block/cache/skewed_cache_rd_only/compare
        if (must_win && ms > ma)
            $fatal(1, "CacheCompare: %s: the skewed cache misses more (%0d) than the set-associative (%0d)",
                   name, ms, ma);
    endtask

    integer ms;
    integer ma;
    integer total_s;    // misses over all scattered working sets
    integer total_a;

    initial begin
        seed = 1;
        $display("Miss rates, 128-line caches (%0d accesses, warm-up %0d):", N_ACCESSES, N_WARM);
        run("random over 64 lines",          0, 64,  1'b0, ms, ma);
        run("random over 128 lines",         0, 128, 1'b0, ms, ma);
        run("random over 192 lines",         0, 192, 1'b0, ms, ma);
        run("random over 256 lines",         0, 256, 1'b0, ms, ma);
        run("conflict: 3 lines of one set",  1, 3,   1'b1, ms, ma);
        run("conflict: 4 lines of one set",  1, 4,   1'b1, ms, ma);
        run("stride 32 lines, 64 elements",  2, 32,  1'b1, ms, ma);
        run("stride 64 lines, 64 elements",  2, 64,  1'b1, ms, ma);
        run("stride 128 lines, 64 elements", 2, 128, 1'b0, ms, ma);
        run("loop of 96 lines",              3, 96,  1'b0, ms, ma);
        run("loop of 128 lines",             3, 128, 1'b0, ms, ma);
        run("loop of 160 lines",             3, 160, 1'b0, ms, ma);
        run("70 % loop of 80, 30 % random",  4, 0,   1'b0, ms, ma);
        // A small scattered set may happen to have no conflict in the set-associative cache
        // while the skewed one's replacement errs a little: the check is on the total.
        total_s = 0;
        total_a = 0;
        for (int t = 0; t < 4; t++) begin
            for (int i = 0; i < 128; i++)
                scattered[i] = line_t'($unsigned($random(seed)) % (1 << 20));
            for (int n = 32; n <= 128; n += 32) begin
                run($sformatf("scattered %0d lines, trial %0d", n, t), 5, n, 1'b0, ms, ma);
                total_s = total_s + ms;
                total_a = total_a + ma;
            end
        end
        $display("scattered, all trials: skewed %0d misses, set-assoc %0d", total_s, total_a);
        if (total_s > total_a)
            $fatal(1, "CacheCompare: scattered working sets: the skewed cache misses more (%0d) than set-assoc (%0d)",
                   total_s, total_a);
        $finish;
    end
endmodule

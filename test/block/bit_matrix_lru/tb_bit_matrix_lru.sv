/* Test of BitMatrixLru.
 *
 * One set of a cache, used the way a cache uses it: the testbench keeps the set's bits (lru
 * = lru_next every clock; garbage at the start, as in a RAM not written) and valid bits, and
 * every clock either hits a random valid way (touch) or fills the victim way (touch, valid);
 * now and then it makes every way invalid, half of the times with new garbage in lru. A
 * model of its own, the time of the last touch of every way, checks victim_way every clock:
 * the lowest invalid way when one is invalid, else the way touched longest ago. In the end
 * the test checks that every case happened: a victim invalid with ways below it valid, the
 * LRU way as victim, a fill of it, a hit of the LRU way, garbage. Runs with WAYS 2, 3, 4 and 8;
 * 20000 clocks on Verilator, 600 on Icarus. Stops at the first mismatch with $fatal.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module TbBitMatrixLruCheck #(
    parameter WAYS = 4
)(
    input  wire  clk,
    output logic done
);
`ifdef VERILATOR
    localparam N_CLOCKS = 20000;
`else
    localparam N_CLOCKS = 600;      // about 1 s at most for a library test
`endif
    localparam WW = $clog2(WAYS);
    localparam LW = WAYS * (WAYS - 1) / 2;

    logic [LW-1:0]   lru;
    logic            touch;
    logic [WW-1:0]   touch_way;
    wire  [LW-1:0]   lru_next;
    logic [WAYS-1:0] valid;
    wire  [WW-1:0]   victim_way;

    integer stamp [WAYS];   // model: time of the last touch of every way
    integer now;
    integer seed;
    integer exp_victim;
    integer w;
    integer n_invalid_above;    // coverage
    integer n_victim_lru;
    integer n_fill_lru;
    integer n_hit_lru;
    integer n_garbage;

    BitMatrixLru #(.WAYS(WAYS)) u_bit_matrix_lru(
        .lru, .touch, .touch_way, .lru_next, .valid, .victim_way);

    // The victim of the model: the lowest invalid way, else the way touched longest ago.
    // A local k, not the function's name: Icarus 13 cannot read the name in the function.
    function automatic integer model_victim();
        integer k;
        for (int i = 0; i < WAYS; i++)
            if (!valid[i])
                return i;
        k = 0;
        for (int i = 1; i < WAYS; i++)
            if (stamp[i] < stamp[k])
                k = i;
        return k;
    endfunction

    // A random valid way; -1 when none is valid.
    function automatic integer random_valid_way();
        integer k;
        if (valid == '0)
            return -1;
        do
            k = $unsigned($random(seed)) % WAYS;
        while (!valid[k]);
        return k;
    endfunction

    task automatic garbage();
        for (int i = 0; i < LW; i++)
            lru[i] = 1'($random(seed));
        n_garbage = n_garbage + 1;
    endtask

    initial begin
        done            = 1'b0;
        seed            = WAYS;
        now             = 0;
        n_invalid_above = 0;
        n_victim_lru    = 0;
        n_fill_lru      = 0;
        n_hit_lru       = 0;
        n_garbage       = 0;
        touch           = 1'b0;
        touch_way       = '0;
        valid           = '0;
        garbage();
        for (int k = 0; k < WAYS; k++)
            stamp[k] = 0;
        for (int n = 0; n < N_CLOCKS; n++) begin
            @(negedge clk);
            touch = 1'b0;
            #1;
            exp_victim = model_victim();
            if (int'(victim_way) != exp_victim)
                $fatal(1, "BitMatrixLru %0d: clock %0d: valid %b: victim %0d, expected %0d", WAYS,
                       n, valid, victim_way, exp_victim);
            if (&valid)
                n_victim_lru = n_victim_lru + 1;
            else if (exp_victim > 0)
                n_invalid_above = n_invalid_above + 1;
            if ($unsigned($random(seed)) % 50 == 0) begin
                // Every way invalid (no touch), half of the times with garbage in lru.
                valid = '0;
                if (1'($random(seed)))
                    garbage();
            end else begin
                w = random_valid_way();
                if (w < 0 || $unsigned($random(seed)) % 4 == 0 ||
                    (!(&valid) && 1'($random(seed)))) begin
                    // Fill the victim.
                    w            = exp_victim;
                    n_fill_lru   = n_fill_lru + (&valid);
                    valid[w]     = 1'b1;
                end else
                    n_hit_lru = n_hit_lru + ((&valid) && w == exp_victim);
                touch     = 1'b1;
                touch_way = WW'(w);
                now       = now + 1;
                stamp[w]  = now;
            end
            #1;
            lru = lru_next;
        end
        if (n_invalid_above == 0 || n_victim_lru == 0 || n_fill_lru == 0 || n_hit_lru == 0 ||
            n_garbage < 2)
            $fatal(1, "BitMatrixLru %0d: a case did not happen: invalid above %0d, victim lru %0d, fill lru %0d, hit lru %0d, garbage %0d",
                   WAYS, n_invalid_above, n_victim_lru, n_fill_lru, n_hit_lru, n_garbage);
        done = 1'b1;
    end
endmodule

module TbBitMatrixLru;
    wire clk;
    wire done2;
    wire done3;
    wire done4;
    wire done8;

    SimClkGen #(.HALF_PERIOD(5)) u_sim_clk_gen(.clk);

    TbBitMatrixLruCheck #(.WAYS(2)) u_check_2(.clk, .done(done2));
    TbBitMatrixLruCheck #(.WAYS(3)) u_check_3(.clk, .done(done3));
    TbBitMatrixLruCheck #(.WAYS(4)) u_check_4(.clk, .done(done4));
    TbBitMatrixLruCheck #(.WAYS(8)) u_check_8(.clk, .done(done8));

    initial begin
        wait (done2 && done3 && done4 && done8);
        $display("PASS");
        $finish;
    end
endmodule

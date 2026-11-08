/* Test of TickGen, behave or struct version.
 *
 * A model of its own, a formula instead of the RTL's counter: in a run of en (from reset or
 * from the clock en rises) the ticks come at fixed clocks. After en rises the first comes
 * floor(div) + 1 clocks later (in the first clock after reset); tick k + 1 comes
 * floor(div) + 1 + c_k clocks after tick k, where c_k = floor(k * f / 2**F) -
 * floor((k - 1) * f / 2**F) is 1 when the k-th addition of the fractional part f to the
 * accumulator carries. The model counts ticks and clocks with integers, so the average
 * period div + 1 is exact. Random runs of en (mostly long, a clock of en = 0 between them
 * now and then), div random while en is 0 (small values often, so that ticks come often;
 * div = 0 too), tick compared in every clock. WIDTH/FRAC_BITS 4/0, 8/0, 12/4 and 10/7;
 * 20000 clocks on Verilator, 4000 on Icarus. Every case must happen (checks named cover): a
 * tick in every clock (div = 0), ticks in two clocks in a row with an integer part 0 and a
 * fraction (FRAC_BITS > 0), a period lengthened by a carry (FRAC_BITS > 0), a period of 9
 * clocks or more, a restart (en low, then the first tick after floor(div) + 1 clocks).
 * Checks named model and cover. Stops at the first failure.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
`include "dark_circuit_test.svh"

module TbTickGenCheck #(
    parameter WIDTH     = 8,
    parameter FRAC_BITS = 0
)(
    input  wire  clk,
    input  wire  rst_n,
    output logic done
);
`ifdef VERILATOR
    localparam N_CYCLES = 20000;
`else
    localparam N_CYCLES = 4000;
`endif
    logic             en;
    logic [WIDTH-1:0] div;
    wire              tick;
    longint           t;            // clock number
    longint           next;         // the clock of the next tick in this run
    longint           k;            // ticks in this run
    logic             running;      // a run of en is going on (else the next clock starts one)
    integer           seed;
    logic seen_every, seen_pair, seen_carry, seen_long, seen_restart;

    TickGen #(.WIDTH(WIDTH), .FRAC_BITS(FRAC_BITS)) u_tick_gen(.clk, .rst_n, .en, .div, .tick);

    function automatic longint int_part();
        return longint'(div) >> FRAC_BITS;
    endfunction

    function automatic longint frac_part();
        return longint'(div) - (int_part() << FRAC_BITS);
    endfunction

    // The carries of the first n additions of the fraction: floor(n * f / 2**F).
    function automatic longint carries(input longint n);
        return (n * frac_part()) >> FRAC_BITS;
    endfunction

    task automatic new_div;
        div = WIDTH'($random(seed));
        if ($random(seed) % 2 == 0)
            div = div & WIDTH'((1 << (FRAC_BITS + 2)) - 1);     // small: ticks often
        if ($random(seed) % 16 == 0)
            div = '0;
    endtask

    initial begin
        longint period;
        logic   exp_tick;
        logic   restarted;      // the run started from en rising, not from reset
        done = 1'b0;
        {seen_every, seen_pair, seen_carry, seen_long, seen_restart} = '0;
        seed      = WIDTH * 8 + FRAC_BITS;
        en        = 1'b0;
        restarted = 1'b0;
        new_div();
        @(posedge rst_n);
        // After reset the counter is 0: a run whose first tick is the first clock.
        t       = 0;
        k       = 0;
        next    = 0;
        running = 1'b1;
        repeat (N_CYCLES) begin
            @(negedge clk);
            // A clock of en = 0 now and then (div may change then), else en.
            if ($random(seed) % 64 == 0) begin
                en = 1'b0;
                new_div();
            end else
                en = 1'b1;
            #1;
            if (!en) begin
                exp_tick  = 1'b0;
                running   = 1'b0;
            end else begin
                if (!running) begin     // the first clock of a run: the count was reloaded
                    running   = 1'b1;
                    restarted = 1'b1;
                    k         = 0;
                    next      = t + int_part();
                end
                exp_tick = t == next;
            end
            if (tick !== exp_tick)
                `DC_TEST_FAIL(model, $sformatf(
                    "TickGen %0d/%0d: clock %0d div %h tick %b, expected %b (tick %0d at %0d)",
                    WIDTH, FRAC_BITS, t, div, tick, exp_tick, k + 1, next))
            if (exp_tick) begin
                if (restarted && k == 0)
                    seen_restart = 1'b1;
                k      = k + 1;
                period = int_part() + 1 + carries(k) - carries(k - 1);
                if (period == 1)                                       seen_every = 1'b1;
                if (FRAC_BITS > 0 && int_part() == 0 && frac_part() != 0 && period == 1)
                    seen_pair = 1'b1;
                if (FRAC_BITS > 0 && carries(k) != carries(k - 1))      seen_carry = 1'b1;
                if (period >= 9)                                       seen_long  = 1'b1;
                next = t + period;
            end
            t = t + 1;
        end
        if (!seen_every || (FRAC_BITS > 0 && (!seen_pair || !seen_carry)) || !seen_long ||
            !seen_restart)
            `DC_TEST_FAIL(cover, $sformatf(
                "TickGen %0d/%0d: every %b pair %b carry %b long %b restart %b", WIDTH, FRAC_BITS,
                seen_every, seen_pair, seen_carry, seen_long, seen_restart))
        done = 1'b1;
    end
endmodule

module TbTickGen;
    `DC_TEST_MUTANT_HOOK(top)

    logic clk;
    logic rst_n;
    wire  done_4_0, done_8_0, done_12_4, done_10_7;

    SimClkGen #(.HALF_PERIOD(5)) u_sim_clk_gen(.clk);
    SimRstGen #(.CYCLES(3))      u_sim_rst_gen(.clk, .rst_n);

    TbTickGenCheck #(.WIDTH(4),  .FRAC_BITS(0)) u_check_4_0(.clk, .rst_n, .done(done_4_0));
    TbTickGenCheck #(.WIDTH(8),  .FRAC_BITS(0)) u_check_8_0(.clk, .rst_n, .done(done_8_0));
    TbTickGenCheck #(.WIDTH(12), .FRAC_BITS(4)) u_check_12_4(.clk, .rst_n, .done(done_12_4));
    TbTickGenCheck #(.WIDTH(10), .FRAC_BITS(7)) u_check_10_7(.clk, .rst_n, .done(done_10_7));

    initial begin
        wait (done_4_0 && done_8_0 && done_12_4 && done_10_7);
        $display("PASS");
        $finish;
    end
endmodule

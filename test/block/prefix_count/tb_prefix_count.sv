/* Test of PrefixCount, behave or struct version.
 *
 * Model: a running count from bit 0 up, every count checked against the one below it.
 * Widths up to 12 bits on Verilator, 8 on Icarus, are exhaustive; wider ones get directed
 * inputs (all zeros, all ones, a single one at every bit) and random inputs of three
 * densities: 3000 on Verilator, 100 on Icarus. Widths 33 and 64 run on Verilator only.
 * Checks named with DC_TEST_FAIL: model (a count differs from the model). Stops at the first
 * failure.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
`include "dark_circuit_test.svh"

module TbPrefixCountCheck #(
    parameter WIDTH = 8
)(
    output logic done
);
`ifdef VERILATOR
    localparam N_RANDOM  = 3000;
    localparam EXH_WIDTH = 12;
`else
    localparam N_RANDOM  = 100;
    localparam EXH_WIDTH = 8;
`endif
    localparam CW         = $clog2(WIDTH + 1);
    localparam EXHAUSTIVE = WIDTH <= EXH_WIDTH;
    localparam WORDS      = (WIDTH + 31) / 32;   // 32-bit words of a random input

    logic [WIDTH-1:0]         in;
    wire  [WIDTH-1:0][CW-1:0] prefix;
    wire  [CW-1:0]            total;
    integer                   seed;

    PrefixCount #(.WIDTH(WIDTH)) u_prefix_count(.in, .prefix, .total);

    // Every count follows from the one below it: prefix[0] = 0, prefix[k+1] = prefix[k] +
    // in[k], total = prefix[WIDTH-1] + in[WIDTH-1].
    task automatic check;
        int exp;
        #1;
        exp = 0;
        for (int k = 0; k < WIDTH; k++) begin
            if (int'(prefix[k]) !== exp)
                `DC_TEST_FAIL(model, $sformatf(
                    "PrefixCount WIDTH=%0d: in %b: prefix[%0d] %0d, expected %0d", WIDTH, in,
                    k, prefix[k], exp))
            exp += int'(in[k]);
        end
        if (int'(total) !== exp)
            `DC_TEST_FAIL(model, $sformatf(
                "PrefixCount WIDTH=%0d: in %b: total %0d, expected %0d", WIDTH, in, total, exp))
    endtask

    // Random bits, 32 at a time.
    function automatic logic [WIDTH-1:0] random_in();
        // The bits above WIDTH are not used.
        /* verilator lint_off UNUSEDSIGNAL */
        logic [WORDS*32-1:0] r;
        /* verilator lint_on UNUSEDSIGNAL */
        for (int i = 0; i < WORDS; i++)
            r[32*i +: 32] = $random(seed);
        return r[WIDTH-1:0];
    endfunction

    initial begin
        done = 1'b0;
        seed = WIDTH;
        if (EXHAUSTIVE) begin
            for (int x = 0; x < (1 << WIDTH); x++) begin
                in = WIDTH'(x);
                check();
            end
        end else begin
            in = '0;
            check();
            in = '1;
            check();
            for (int k = 0; k < WIDTH; k++) begin          // a single one at k
                in = WIDTH'(1) << k;
                check();
            end
            for (int i = 0; i < N_RANDOM; i++) begin        // sparse, half, dense
                in = random_in();
                if (i % 3 == 0)
                    in = in & random_in() & random_in();
                else if (i % 3 == 2)
                    in = in | random_in();
                check();
            end
        end
        done = 1'b1;
    end
endmodule

module TbPrefixCount;
    `DC_TEST_MUTANT_HOOK(top)

    wire done_1, done_2, done_3, done_5, done_8, done_12, done_33, done_64;

    TbPrefixCountCheck #(.WIDTH(1))  u_check_1  (.done(done_1));
    TbPrefixCountCheck #(.WIDTH(2))  u_check_2  (.done(done_2));
    TbPrefixCountCheck #(.WIDTH(3))  u_check_3  (.done(done_3));
    TbPrefixCountCheck #(.WIDTH(5))  u_check_5  (.done(done_5));
    TbPrefixCountCheck #(.WIDTH(8))  u_check_8  (.done(done_8));
    TbPrefixCountCheck #(.WIDTH(12)) u_check_12 (.done(done_12));
`ifdef VERILATOR
    // The wide struct versions take seconds to elaborate on event-driven Icarus.
    TbPrefixCountCheck #(.WIDTH(33)) u_check_33 (.done(done_33));
    TbPrefixCountCheck #(.WIDTH(64)) u_check_64 (.done(done_64));
`else
    assign done_33 = 1'b1;
    assign done_64 = 1'b1;
`endif

    initial begin
        wait (done_1 && done_2 && done_3 && done_5 && done_8 && done_12 && done_33 && done_64);
        $display("PASS");
        $finish;
    end
endmodule

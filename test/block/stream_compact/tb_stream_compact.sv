/* Test of StreamCompact, behave or struct version.
 *
 * Model: the valid elements counted, then placed from the top element down (the last valid
 * one in slot count - 1), unlike either version. Widths up to 12 elements on Verilator, 8 on
 * Icarus, are exhaustive over the valid bits; wider ones get directed cases (none valid, all
 * valid, exactly MAX valid, MAX + 1 valid) and random ones of three densities: 3000 on
 * Verilator, 30 on Icarus; widths 40 and 33 on Verilator only. The data are the elements'
 * positions in every other case (zero suppression), random in the others. In the end every
 * kind must have happened. Checks named with DC_TEST_FAIL: model (a result differs from the
 * model), cover (a kind of case did not happen). Stops at the first failure.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
`include "dark_circuit_test.svh"

module TbStreamCompactCheck #(
    parameter WIDTH      = 8,
    parameter MAX        = 4,
    parameter DATA_WIDTH = 3
)(
    output logic done
);
`ifdef VERILATOR
    localparam N_RANDOM  = 3000;
    localparam EXH_WIDTH = 12;
`else
    localparam N_RANDOM  = 30;
    localparam EXH_WIDTH = 8;
`endif
    localparam CW         = $clog2(WIDTH + 1);
    localparam EXHAUSTIVE = WIDTH <= EXH_WIDTH;
    localparam WORDS      = (WIDTH + 31) / 32;   // 32-bit words of random valid bits

    typedef logic [DATA_WIDTH-1:0] data_t;

    logic [WIDTH-1:0]                 valid;
    logic [WIDTH-1:0][DATA_WIDTH-1:0] data;
    wire  [MAX-1:0]                   out_valid;
    wire  [MAX-1:0][DATA_WIDTH-1:0]   out_data;
    wire  [CW-1:0]                    count;
    wire                              overflow;
    integer                           seed;
    int                               n_case;
    // Coverage: kinds of cases that happened.
    logic                             seen_none;        // no element valid
    logic                             seen_all;         // every element valid
    logic                             seen_full;        // exactly MAX valid
    logic                             seen_overflow;    // more than MAX valid

    StreamCompact #(.WIDTH(WIDTH), .MAX(MAX), .DATA_WIDTH(DATA_WIDTH)) u_stream_compact(
        .valid, .data, .out_valid, .out_data, .count, .overflow);

    // The data of a case: positions in every other one, random in the others.
    task automatic set_data;
        for (int k = 0; k < WIDTH; k++)
            data[k] = (n_case % 2 == 0) ? data_t'(k) : data_t'($random(seed));
        n_case++;
    endtask

    // The ones in v.
    function automatic int ones(logic [WIDTH-1:0] v);
        int n;
        n = 0;
        for (int i = 0; i < WIDTH; i++)
            n += int'(v[i]);
        return n;
    endfunction

    task automatic check;
        int                        n;
        int                        slot;
        logic  [MAX-1:0]           exp_valid;
        data_t [MAX-1:0]           exp_data;
        n = ones(valid);
        // From the top element down: the last valid one goes to slot n - 1.
        exp_valid = '0;
        exp_data  = '0;
        slot      = n;
        for (int k = WIDTH - 1; k >= 0; k--)
            if (valid[k]) begin
                slot--;
                if (slot < MAX) begin
                    exp_valid[slot] = 1'b1;
                    exp_data[slot]  = data[k];
                end
            end
        #1;
        if (int'(count) !== n || overflow !== (n > MAX))
            `DC_TEST_FAIL(model, $sformatf(
                "StreamCompact %0d/%0d: valid %b: count %0d overflow %b, expected %0d %b",
                WIDTH, MAX, valid, count, overflow, n, n > MAX))
        if (out_valid !== exp_valid || out_data !== exp_data)
            `DC_TEST_FAIL(model, $sformatf(
                "StreamCompact %0d/%0d: valid %b data %h: slots %b %h, expected %b %h",
                WIDTH, MAX, valid, data, out_valid, out_data, exp_valid, exp_data))
        seen_none     |= n == 0;
        seen_all      |= n == WIDTH;
        seen_full     |= n == MAX;
        seen_overflow |= n > MAX;
    endtask

    // Random bits, 32 at a time.
    function automatic logic [WIDTH-1:0] random_valid();
        // The bits above WIDTH are not used.
        /* verilator lint_off UNUSEDSIGNAL */
        logic [WORDS*32-1:0] r;
        /* verilator lint_on UNUSEDSIGNAL */
        for (int i = 0; i < WORDS; i++)
            r[32*i +: 32] = $random(seed);
        return r[WIDTH-1:0];
    endfunction

    // n valid elements at random places: a random element made valid until there are n.
    function automatic logic [WIDTH-1:0] n_valid(int n);
        logic [WIDTH-1:0] r;
        int               pick;
        r = '0;
        while (ones(r) < n) begin
            pick = int'($unsigned($random(seed)) % WIDTH);
            for (int k = 0; k < WIDTH; k++)
                if (k == pick)
                    r[k] = 1'b1;
        end
        return r;
    endfunction

    initial begin
        done          = 1'b0;
        seed          = WIDTH * 100 + MAX;
        n_case        = 0;
        seen_none     = 1'b0;
        seen_all      = 1'b0;
        seen_full     = 1'b0;
        seen_overflow = 1'b0;
        if (EXHAUSTIVE) begin
            for (int x = 0; x < (1 << WIDTH); x++) begin
                valid = WIDTH'(x);
                set_data();
                check();
            end
        end else begin
            for (int i = 0; i < 2; i++) begin               // positions, random data
                valid = '0;
                set_data();
                check();
                valid = '1;
                set_data();
                check();
                valid = n_valid(MAX);
                set_data();
                check();
                if (MAX < WIDTH) begin
                    valid = n_valid(MAX + 1);
                    set_data();
                    check();
                end
            end
            for (int i = 0; i < N_RANDOM; i++) begin        // sparse, half, dense
                valid = random_valid();
                if (i % 3 == 0)
                    valid = valid & random_valid() & random_valid();
                else if (i % 3 == 2)
                    valid = valid | random_valid();
                set_data();
                check();
            end
        end
        if (!seen_none || !seen_all || !seen_full || (MAX < WIDTH && !seen_overflow))
            `DC_TEST_FAIL(cover, $sformatf(
                "StreamCompact %0d/%0d: none %b, all %b, full %b, overflow %b", WIDTH, MAX,
                seen_none, seen_all, seen_full, seen_overflow))
        done = 1'b1;
    end
endmodule

module TbStreamCompact;
    `DC_TEST_MUTANT_HOOK(top)

    wire done_1_1, done_2_1, done_3_3, done_5_2, done_8_4, done_12_5, done_24_8, done_40_16,
         done_33_33;

    TbStreamCompactCheck #(.WIDTH(1),  .MAX(1),  .DATA_WIDTH(1)) u_check_1_1  (.done(done_1_1));
    TbStreamCompactCheck #(.WIDTH(2),  .MAX(1),  .DATA_WIDTH(2)) u_check_2_1  (.done(done_2_1));
    TbStreamCompactCheck #(.WIDTH(3),  .MAX(3),  .DATA_WIDTH(2)) u_check_3_3  (.done(done_3_3));
    TbStreamCompactCheck #(.WIDTH(5),  .MAX(2),  .DATA_WIDTH(3)) u_check_5_2  (.done(done_5_2));
    TbStreamCompactCheck #(.WIDTH(8),  .MAX(4),  .DATA_WIDTH(3)) u_check_8_4  (.done(done_8_4));
    TbStreamCompactCheck #(.WIDTH(12), .MAX(5),  .DATA_WIDTH(4)) u_check_12_5 (.done(done_12_5));
    TbStreamCompactCheck #(.WIDTH(24), .MAX(8),  .DATA_WIDTH(5)) u_check_24_8 (.done(done_24_8));
`ifdef VERILATOR
    // The wide struct versions take seconds to elaborate on event-driven Icarus.
    TbStreamCompactCheck #(.WIDTH(40), .MAX(16), .DATA_WIDTH(6)) u_check_40_16(.done(done_40_16));
    TbStreamCompactCheck #(.WIDTH(33), .MAX(33), .DATA_WIDTH(6)) u_check_33_33(.done(done_33_33));
`else
    assign done_40_16 = 1'b1;
    assign done_33_33 = 1'b1;
`endif

    initial begin
        wait (done_1_1 && done_2_1 && done_3_3 && done_5_2 && done_8_4 && done_12_5 &&
              done_24_8 && done_40_16 && done_33_33);
        $display("PASS");
        $finish;
    end
endmodule

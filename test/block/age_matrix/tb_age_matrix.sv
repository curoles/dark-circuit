/* Test of AgeMatrix.
 *
 * The testbench keeps the state (ages = ages_next every clock, all zeros at the start) and a
 * model of its own: the time of the last touch of every entry (at the start entry k at
 * k - SIZE: SIZE-1 the newest). Every clock random inputs: a touch (half of the clocks) of a
 * random entry, a mask (random, all ones, 0, one entry); the test checks that ages encodes
 * the order of the model (bit of (i, j), i < j: i touched later than j) and that
 * select_oldest is the entry of the mask touched longest ago (0 for an empty mask). Every 500
 * clocks garbage goes into ages, then every entry is touched once in a random order: from
 * then on the order must be the order of these touches (no checks in between). In the end
 * the test checks that every case happened: an empty mask, all ones, one entry, a touch of
 * the oldest entry and of the newest. Runs with SIZE 2, 3, 5, 8 and, on Verilator, 16;
 * 20000 clocks on Verilator, 600 on Icarus. Stops at the first mismatch with $fatal.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module TbAgeMatrixCheck #(
    parameter SIZE = 8
)(
    input  wire  clk,
    output logic done
);
`ifdef VERILATOR
    localparam N_CLOCKS = 20000;
`else
    localparam N_CLOCKS = 600;      // about 1 s at most for a library test
`endif
    localparam IW = $clog2(SIZE);
    localparam AW = SIZE * (SIZE - 1) / 2;

    logic [AW-1:0]   ages;
    logic            touch;
    logic [IW-1:0]   touch_index;
    wire  [AW-1:0]   ages_next;
    logic [SIZE-1:0] select_mask;
    wire  [SIZE-1:0] select_oldest;

    integer stamp [SIZE];   // model: time of the last touch of every entry
    integer now;
    integer perm  [SIZE];   // order of the touches after garbage
    integer seed;
    integer n_empty;        // coverage
    integer n_full;
    integer n_one;
    integer n_touch_oldest;
    integer n_touch_newest;

    AgeMatrix #(.SIZE(SIZE)) u_age_matrix(
        .ages, .touch, .touch_index, .ages_next, .select_mask, .select_oldest);

    // The ages of the model: bit of (i, j), i < j, is 1 when i was touched later.
    function automatic [AW-1:0] model_ages();
        integer p;
        p = 0;
        for (int i = 0; i < SIZE; i++)
            for (int j = i + 1; j < SIZE; j++) begin
                model_ages[p] = stamp[i] > stamp[j];
                p = p + 1;
            end
    endfunction

    // The entry of mask touched longest ago, one-hot; 0 for an empty mask.
    function automatic [SIZE-1:0] model_oldest(input [SIZE-1:0] mask);
        integer k;
        k = -1;
        for (int i = 0; i < SIZE; i++)
            if (mask[i] && (k < 0 || stamp[i] < stamp[k]))
                k = i;
        model_oldest = '0;
        if (k >= 0)
            model_oldest[k] = 1'b1;
    endfunction

    function automatic integer oldest_entry();
        integer k;
        k = 0;
        for (int i = 1; i < SIZE; i++)
            if (stamp[i] < stamp[k])
                k = i;
        return k;
    endfunction

    function automatic integer newest_entry();
        integer k;
        k = 0;
        for (int i = 1; i < SIZE; i++)
            if (stamp[i] > stamp[k])
                k = i;
        return k;
    endfunction

    function automatic [SIZE-1:0] random_mask();
        integer r;
        r = $unsigned($random(seed)) % 8;
        if (r == 0)
            return '0;
        if (r == 1)
            return '1;
        if (r == 2)
            return SIZE'(1) << ($unsigned($random(seed)) % SIZE);
        for (int i = 0; i < SIZE; i++)
            random_mask[i] = 1'($random(seed));
    endfunction

    // Garbage into ages, then every entry touched once in a random order (no checks).
    task automatic scramble();
        // k is an index below SIZE: its high bits are always 0.
        /* verilator lint_off UNUSEDSIGNAL */
        integer k;
        /* verilator lint_on UNUSEDSIGNAL */
        integer t;
        for (int i = 0; i < AW; i++)
            ages[i] = 1'($random(seed));
        for (int i = 0; i < SIZE; i++)
            perm[i] = i;
        for (int i = SIZE - 1; i > 0; i--) begin
            k       = $unsigned($random(seed)) % (i + 1);
            t       = perm[i];
            perm[i] = perm[k];
            perm[k] = t;
        end
        for (int i = 0; i < SIZE; i++) begin
            @(negedge clk);
            touch       = 1'b1;
            touch_index = IW'(perm[i]);
            select_mask = random_mask();
            #1;
            ages        = ages_next;
            now         = now + 1;
            stamp[perm[i]] = now;
        end
    endtask

    initial begin
        done           = 1'b0;
        seed           = SIZE;
        now            = 0;
        n_empty        = 0;
        n_full         = 0;
        n_one          = 0;
        n_touch_oldest = 0;
        n_touch_newest = 0;
        ages           = '0;
        touch          = 1'b0;
        touch_index    = '0;
        select_mask    = '0;
        for (int k = 0; k < SIZE; k++)
            stamp[k] = k - SIZE;
        for (int n = 0; n < N_CLOCKS; n++) begin
            if (n % 500 == 250)
                scramble();
            @(negedge clk);
            touch       = 1'($random(seed));
            touch_index = IW'($unsigned($random(seed)) % SIZE);
            select_mask = random_mask();
            #1;
            if (ages !== model_ages())
                $fatal(1, "AgeMatrix %0d: clock %0d: ages %b, expected %b", SIZE, n, ages,
                       model_ages());
            if (select_oldest !== model_oldest(select_mask))
                $fatal(1, "AgeMatrix %0d: clock %0d: mask %b selects %b, expected %b", SIZE, n,
                       select_mask, select_oldest, model_oldest(select_mask));
            n_empty = n_empty + (select_mask == '0);
            n_full  = n_full + (select_mask == '1);
            n_one   = n_one + ($countones(select_mask) == 1);
            if (touch) begin
                n_touch_oldest = n_touch_oldest + (int'(touch_index) == oldest_entry());
                n_touch_newest = n_touch_newest + (int'(touch_index) == newest_entry());
            end
            ages = ages_next;
            if (touch) begin
                now                = now + 1;
                stamp[touch_index] = now;
            end
        end
        if (n_empty == 0 || n_full == 0 || n_one == 0 || n_touch_oldest == 0 ||
            n_touch_newest == 0)
            $fatal(1, "AgeMatrix %0d: a case did not happen: empty %0d, full %0d, one %0d, touch oldest %0d, newest %0d",
                   SIZE, n_empty, n_full, n_one, n_touch_oldest, n_touch_newest);
        done = 1'b1;
    end
endmodule

module TbAgeMatrix;
    wire clk;
    wire done2;
    wire done3;
    wire done5;
    wire done8;
    wire done16;

    SimClkGen #(.HALF_PERIOD(5)) u_sim_clk_gen(.clk);

    TbAgeMatrixCheck #(.SIZE(2)) u_check_2(.clk, .done(done2));
    TbAgeMatrixCheck #(.SIZE(3)) u_check_3(.clk, .done(done3));
    TbAgeMatrixCheck #(.SIZE(5)) u_check_5(.clk, .done(done5));
    TbAgeMatrixCheck #(.SIZE(8)) u_check_8(.clk, .done(done8));
`ifdef VERILATOR
    TbAgeMatrixCheck #(.SIZE(16)) u_check_16(.clk, .done(done16));
`else
    assign done16 = 1'b1;   // Icarus: the time (about 1 s at most for a library test)
`endif

    initial begin
        wait (done2 && done3 && done5 && done8 && done16);
        $display("PASS");
        $finish;
    end
endmodule

/* Test of ArgMaxTree, behave or struct version.
 *
 * Model: two passes, unlike either version: first the largest valid value, then the lowest
 * index that has it. Every configuration gets the cases of every kind: no input valid, one
 * input valid at each index, all valid with one largest value at each index, ties of the
 * largest value (the lowest index must win), values 0 and all ones. Small configurations
 * (N * (WIDTH + 1) <= 12 bits of input) are exhaustive; the others get random inputs: 3000
 * on Verilator, 100 on Icarus. In the end every kind must have happened. Checks named with
 * DC_TEST_FAIL: model (a result differs from the model), cover (a kind of case did not
 * happen). Stops at the first failure.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
`include "dark_circuit_test.svh"

module TbArgMaxTreeCheck #(
    parameter N     = 8,
    parameter WIDTH = 8
)(
    output logic done
);
`ifdef VERILATOR
    localparam N_RANDOM = 3000;
`else
    localparam N_RANDOM = 100;
`endif
    localparam IW         = (N > 1) ? $clog2(N) : 1;
    localparam IN_BITS    = N * (WIDTH + 1);
    localparam EXHAUSTIVE = IN_BITS <= 12;

    typedef logic [WIDTH-1:0] value_t;
    localparam value_t ONES = '1;

    logic [N-1:0][WIDTH-1:0] values;
    logic [N-1:0]            valid;
    wire                     max_valid;
    wire  [WIDTH-1:0]        max_value;
    wire  [IW-1:0]           max_index;
    integer                  seed;
    // Coverage: kinds of cases that happened.
    logic                    seen_none;     // no input valid
    logic                    seen_tie;      // the largest value at two or more valid inputs
    logic [N-1:0]            seen_index;    // max_index was k

    ArgMaxTree #(.N(N), .WIDTH(WIDTH)) u_arg_max_tree(
        .values, .valid, .max_valid, .max_value, .max_index);

    task automatic check;
        logic   exp_valid;
        value_t exp_value;
        int     exp_index;
        int     ties;
        exp_valid = |valid;
        exp_value = '0;
        exp_index = 0;
        ties      = 0;
        for (int k = 0; k < N; k++)
            if (valid[k] && values[k] > exp_value)
                exp_value = values[k];
        for (int k = N - 1; k >= 0; k--)
            if (valid[k] && values[k] == exp_value) begin
                exp_index = k;
                ties++;
            end
        #1;
        if (max_valid !== exp_valid || max_value !== exp_value ||
            int'(max_index) !== exp_index)
            `DC_TEST_FAIL(model, $sformatf(
                "ArgMaxTree N=%0d WIDTH=%0d: values %h valid %b: got %b %h %0d, expected %b %h %0d",
                N, WIDTH, values, valid, max_valid, max_value, max_index, exp_valid, exp_value,
                exp_index))
        if (!exp_valid)
            seen_none = 1'b1;
        else begin
            seen_index[exp_index] = 1'b1;
            if (ties > 1)
                seen_tie = 1'b1;
        end
    endtask

    function automatic value_t random_value();
        return value_t'($random(seed));
    endfunction

    initial begin
        done       = 1'b0;
        seen_none  = 1'b0;
        seen_tie   = 1'b0;
        seen_index = '0;
        seed       = N * 100 + WIDTH;
        if (EXHAUSTIVE) begin
            for (int x = 0; x < (1 << IN_BITS); x++) begin
                {valid, values} = IN_BITS'(x);
                check();
            end
        end else begin
            valid = '0;                                     // none valid
            values = '0;
            check();
            for (int k = 0; k < N; k++) begin               // one valid input at k
                for (int j = 0; j < N; j++)
                    values[j] = ONES;
                valid = N'(1) << k;
                values[k] = random_value();
                check();
            end
            for (int k = 0; k < N; k++) begin               // all valid, the largest at k
                for (int j = 0; j < N; j++)
                    values[j] = random_value() >> 1;        // below ONES
                values[k] = ONES;
                valid = '1;
                check();
            end
            for (int k = 0; k + 1 < N; k++) begin           // a tie at k and N - 1: k wins
                for (int j = 0; j < N; j++)
                    values[j] = '0;
                values[k]     = ONES;
                values[N - 1] = ONES;
                valid = '1;
                check();
            end
            for (int i = 0; i < N_RANDOM; i++) begin        // random, few or many valid
                for (int j = 0; j < N; j++)
                    values[j] = random_value();
                valid = N'($random(seed)) & (i % 2 == 0 ? N'($random(seed)) : '1);
                check();
            end
        end
        if (!seen_none || !(&seen_index) || (N > 1 && !seen_tie))
            `DC_TEST_FAIL(cover, $sformatf(
                "ArgMaxTree N=%0d WIDTH=%0d: none %b, tie %b, indices %b", N, WIDTH, seen_none,
                seen_tie, seen_index))
        done = 1'b1;
    end
endmodule

module TbArgMaxTree;
    `DC_TEST_MUTANT_HOOK(top)

    wire done_1_3, done_2_1, done_3_2, done_5_1, done_4_2, done_8_3, done_31_3, done_33_8;

    TbArgMaxTreeCheck #(.N(1),  .WIDTH(3)) u_check_1_3  (.done(done_1_3));
    TbArgMaxTreeCheck #(.N(2),  .WIDTH(1)) u_check_2_1  (.done(done_2_1));
    TbArgMaxTreeCheck #(.N(3),  .WIDTH(2)) u_check_3_2  (.done(done_3_2));
    TbArgMaxTreeCheck #(.N(5),  .WIDTH(1)) u_check_5_1  (.done(done_5_1));
    TbArgMaxTreeCheck #(.N(4),  .WIDTH(2)) u_check_4_2  (.done(done_4_2));
    TbArgMaxTreeCheck #(.N(8),  .WIDTH(3)) u_check_8_3  (.done(done_8_3));
    TbArgMaxTreeCheck #(.N(31), .WIDTH(3)) u_check_31_3 (.done(done_31_3));
    TbArgMaxTreeCheck #(.N(33), .WIDTH(8)) u_check_33_8 (.done(done_33_8));

    initial begin
        wait (done_1_3 && done_2_1 && done_3_2 && done_5_1 && done_4_2 && done_8_3 &&
              done_31_3 && done_33_8);
        $display("PASS");
        $finish;
    end
endmodule

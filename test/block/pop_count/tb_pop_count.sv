/* Test of PopCount, behave or struct version.
 *
 * Model: $countones. WIDTH 1, 2, 3, 5, 8: exhaustive. WIDTH 31, 32, 33, 64: 0, all ones,
 * every one-hot word, for every count k a word of k ones rotated by a random amount, then
 * random words: 5000 on Verilator, 100 on Icarus. In the end the test checks that every
 * count 0..WIDTH happened. Stops at the first mismatch with $fatal.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module TbPopCountCheck #(
    parameter WIDTH = 32
)(
    output logic done
);
`ifdef VERILATOR
    localparam N_RANDOM = 5000;
`else
    localparam N_RANDOM = 100;
`endif
    localparam CW         = $clog2(WIDTH + 1);
    localparam EXHAUSTIVE = WIDTH <= 8;

    typedef logic [WIDTH-1:0] word_t;
    localparam word_t ONES = '1;

    word_t           in;
    wire   [CW-1:0]  count;
    logic  [WIDTH:0] seen;      // coverage: counts 0..WIDTH that happened
    integer          seed;

    PopCount #(.WIDTH(WIDTH)) u_pop_count(.in, .count);

    task automatic check(input word_t x);
        int exp;
        in = x;
        #1;
        exp = $countones(x);
        if (int'(count) !== exp)
            $fatal(1, "PopCount %0d: in=%h got %0d, expected %0d", WIDTH, x, count, exp);
        seen[exp] = 1'b1;
    endtask

    // x rotated left by r % WIDTH.
    function automatic word_t rotate(input word_t x, input logic [7:0] r);
        int s;
        s = int'(r) % WIDTH;
        return (s == 0) ? x : (x << s) | (x >> (WIDTH - s));
    endfunction

    // A random word: 16 random bits at a time.
    function automatic word_t random_word();
        word_t x;
        x = '0;
        for (int i = 0; i < WIDTH; i += 16)
            x = word_t'({x, 16'($random(seed))});
        return x;
    endfunction

    initial begin
        done = 1'b0;
        seen = '0;
        seed = WIDTH;
        if (EXHAUSTIVE) begin
            for (int v = 0; v < (1 << WIDTH); v++)
                check(word_t'(v));
        end else begin
            check('0);
            check(ONES);
            for (int b = 0; b < WIDTH; b++)
                check(word_t'(1) << b);
            for (int k = 0; k <= WIDTH; k++)
                check(rotate(ONES >> (WIDTH - k), 8'($random(seed))));
            for (int i = 0; i < N_RANDOM; i++)
                check(random_word());
        end
        if (!(&seen))
            $fatal(1, "PopCount %0d: a count did not happen: %b", WIDTH, seen);
        done = 1'b1;
    end
endmodule

module TbPopCount;
    wire [8:0] done;

    TbPopCountCheck #(.WIDTH(1))  u_check_1 (.done(done[0]));
    TbPopCountCheck #(.WIDTH(2))  u_check_2 (.done(done[1]));
    TbPopCountCheck #(.WIDTH(3))  u_check_3 (.done(done[2]));
    TbPopCountCheck #(.WIDTH(5))  u_check_5 (.done(done[3]));
    TbPopCountCheck #(.WIDTH(8))  u_check_8 (.done(done[4]));
    TbPopCountCheck #(.WIDTH(31)) u_check_31(.done(done[5]));
    TbPopCountCheck #(.WIDTH(32)) u_check_32(.done(done[6]));
    TbPopCountCheck #(.WIDTH(33)) u_check_33(.done(done[7]));
    TbPopCountCheck #(.WIDTH(64)) u_check_64(.done(done[8]));

    initial begin
        wait (&done);
        $finish;
    end
endmodule

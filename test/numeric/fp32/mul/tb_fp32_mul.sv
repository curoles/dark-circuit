/* Test of Fp32CombMultiplier and Fp32PipelinedMultiplier: products against an exact
 * reference.
 *
 * The reference converts both operands to real exactly, multiplies in real (exact: a
 * 48-bit product fits the 53-bit mantissa of a double) and truncates the double to
 * single precision by its bits. Operands: edge cases (products below and above 2,
 * largest mantissas, signs, zero and subnormal operands) and random normal operands
 * whose product stays normal; overflow and underflow are not handled by the multipliers
 * and not tested. Both multipliers get the same operands, a new pair at every falling
 * clock edge: the combinational product is checked at once, the pipelined one three
 * falling edges later. Stops at the first mismatch with $fatal.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module TbFp32Mul;
    import Fp32Pkg::*;

    localparam int RANDOM_PAIRS = 100000;
    localparam int LATENCY      = 3;        // clocks of Fp32PipelinedMultiplier

    typedef struct packed {
        fp32_t a;           // operands
        fp32_t b;
        fp32_t product;     // expected product
    } case_t;

    logic  clk;
    logic  rst_n;
    fp32_t a;
    fp32_t b;
    fp32_t comb_result;
    fp32_t pipe_result;
    case_t in_flight[$];    // pairs in the pipelined multiplier, oldest first

    Fp32CombMultiplier u_fp32_comb_multiplier(.a, .b, .result(comb_result));
    Fp32PipelinedMultiplier u_fp32_pipelined_multiplier(
        .clk, .rst_n, .a, .b, .result(pipe_result));

    initial clk = 1'b0;
    always #5 clk = ~clk;

    // x as a real, exactly (x normal): the same value as a double.
    function automatic real to_real(fp32_t x);
        logic [10:0] e;
        e = {3'b0, x.exp} + 11'd896;    // rebias: 1023 - 127
        return $bitstoreal({x.sign, e, x.mant, 29'b0});
    endfunction

    // a * b truncated to single precision; 0 when an operand has exponent 0.
    function automatic fp32_t expected(fp32_t x, fp32_t y);
        // d[28:0]: the fraction bits that truncation to single precision drops.
        /* verilator lint_off UNUSEDSIGNAL */
        logic [63:0] d;
        /* verilator lint_on UNUSEDSIGNAL */
        logic [10:0] e;
        if (x.exp == 0 || y.exp == 0)
            return '0;
        d = $realtobits(to_real(x) * to_real(y));
        e = d[62:52] - 11'd896;
        if (e[10:8] != 0)
            $fatal(1, "%h * %h: product out of the normal range, not a test case", x, y);
        return {d[63], e[7:0], d[51:29]};
    endfunction

    // A random normal operand with exponent 64..190: the product of two stays normal.
    function automatic fp32_t random_operand();
        fp32_t x;
        x     = $urandom;
        x.exp = 8'd64 + x.exp % 8'd127;
        return x;
    endfunction

    // One operand pair at a falling edge: the combinational product is checked at once,
    // the pipelined one LATENCY falling edges later.
    task automatic check(fp32_t x, fp32_t y);
        case_t c;
        @(negedge clk);
        if (in_flight.size() == LATENCY) begin
            c = in_flight.pop_front();
            if (pipe_result !== c.product)
                $fatal(1, "pipelined %h * %h: result %h, expected %h",
                       c.a, c.b, pipe_result, c.product);
        end
        a = x;
        b = y;
        c = {x, y, expected(x, y)};
        #1;
        if (comb_result !== c.product)
            $fatal(1, "combinational %h * %h: result %h, expected %h",
                   x, y, comb_result, c.product);
        in_flight.push_back(c);
    endtask

    initial begin
        a     = '0;
        b     = '0;
        rst_n = 1'b0;
        repeat (2) @(negedge clk);
        rst_n = 1'b1;
        // The reference itself, on products known exactly.
        if (expected(32'h3f80_0000, 32'h3f80_0000) !== 32'h3f80_0000 ||
            expected(32'h3fc0_0000, 32'h3fc0_0000) !== 32'h4010_0000 ||
            expected(32'hc000_0000, 32'h4040_0000) !== 32'hc0c0_0000)
            $fatal(1, "the reference model is wrong");
        check(32'h3f80_0000, 32'h3f80_0000);    // 1.0 * 1.0: product below 2
        check(32'h3fc0_0000, 32'h3fc0_0000);    // 1.5 * 1.5: product above 2
        check(32'h3fff_ffff, 32'h3fff_ffff);    // largest mantissas: truncation shows
        check(32'hc000_0000, 32'h4040_0000);    // -2 * 3
        check(32'h0000_0000, 32'h40a0_0000);    // 0 * 5
        check(32'h8000_0000, 32'h40a0_0000);    // -0 * 5: gives 0
        check(32'h40a0_0000, 32'h0000_0001);    // 5 * subnormal: gives 0
        for (int i = 0; i < RANDOM_PAIRS; i++)
            check(random_operand(), random_operand());
        repeat (LATENCY)                        // the last pairs come out
            check('0, '0);
        $finish;
    end

endmodule

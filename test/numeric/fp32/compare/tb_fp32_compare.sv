/* Test of Fp32Compare, Fp32MinMax (both NaN rules), Fp32Class and Fp32SignInject on
 * TestFloat's compare cases.
 *
 * +cases=<dir>: the case files <dir>/<function>.rne of f32_eq, f32_lt, f32_le (signalling),
 * f32_eq_signaling, f32_lt_quiet, f32_le_quiet that testfloat_gen wrote (dc_testfloat_cases,
 * cmake/testfloat.cmake), a line per case in hex: a, b, the predicate (0 or 1), the flags.
 * Fp32Compare's predicate must be TestFloat's, its NV that of a quiet compare (snan) or a
 * signalling one (unordered). TestFloat has no minimum, maximum, class or sign injection, so
 * on every pair of f32_lt_quiet these are checked against models of this file that take
 * TestFloat's a < b and NV, and the values as reals (to_real): the minimum and
 * maximum by both rules (a NaN loses to a number, or wins as the default NaN; -0 below +0),
 * the class of a and of b, and the three sign injections. Stops at the first mismatch with
 * $fatal.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module TbFp32Compare;
    import Fp32Pkg::*;
    import FpPkg::*;

    localparam logic [31:0] SIGN = 32'h8000_0000;
    localparam logic [31:0] DNAN = 32'h7fc0_0000;   // the default NaN

    fp32_t       a;
    fp32_t       b;
    logic        eq;
    logic        lt;
    logic        le;
    logic        unordered;
    logic        snan;
    logic        max;
    fp32_t       min_max_number;    // Fp32MinMax, MINMAX_NUMBER
    fp32_t       min_max_nan;       // Fp32MinMax, MINMAX_NAN
    logic        nv_number;
    logic        nv_nan;
    class_t      class_a;
    class_t      class_b;
    sgnj_op_e    sgnj_op;
    fp32_t       sgnj;

    string       dir;
    string       name;
    integer      fd;
    integer      n;
    integer      total;
    logic [31:0] va;
    logic [31:0] vb;
    logic [3:0]  want;          // the predicate
    logic [7:0]  want_flags;

    Fp32Compare u_compare(.a, .b, .eq, .lt, .le, .unordered, .snan);
    Fp32MinMax #(.NAN_RULE(MINMAX_NUMBER)) u_min_max_number(
        .a, .b, .max, .result(min_max_number), .nv(nv_number));
    Fp32MinMax #(.NAN_RULE(MINMAX_NAN)) u_min_max_nan(
        .a, .b, .max, .result(min_max_nan), .nv(nv_nan));
    Fp32Class u_class_a(.x(a), .c(class_a));
    Fp32Class u_class_b(.x(b), .c(class_b));
    Fp32SignInject u_sign_inject(.a, .b, .op(sgnj_op), .result(sgnj));

    // x as a real, exactly: a double with the exponent rebiased (normal, infinity, NaN), or the
    // fraction times 2^-149 (subnormal, zero). ($bitstoshortreal: not in Verilator.)
    function automatic real to_real(input logic [31:0] x);
        real r;
        if (x[30:23] == '0) begin
            r = $itor(x[22:0]) * 1.401298464324817e-45;
            return x[31] ? -r : r;
        end
        if (x[30:23] == '1)
            return $bitstoreal({x[31], 11'h7ff, x[22:0], 29'b0});
        return $bitstoreal({x[31], {3'b0, x[30:23]} + 11'd896, x[22:0], 29'b0});
    endfunction

    // x (an fp32 but its sign) is a NaN: exponent field all ones, fraction not 0. From the
    // bits: a real NaN's r != r is 0 in Verilator.
    function automatic logic is_nan(input logic [30:0] x);
        return x[30:23] == '1 && x[22:0] != '0;
    endfunction

    // The minimum or maximum by a NaN rule, from TestFloat's x < y.
    function automatic logic [31:0] min_max_model(input logic nan_wins, input logic mx,
                                                  input logic [31:0] x, input logic [31:0] y,
                                                  input logic x_lt_y);
        if (is_nan(x[30:0]) && is_nan(y[30:0]))
            return DNAN;
        if (is_nan(x[30:0]) || is_nan(y[30:0]))
            return nan_wins ? DNAN : is_nan(x[30:0]) ? y : x;
        if (to_real(x) == 0.0 && to_real(y) == 0.0)
            return (mx ? x[31] && y[31] : x[31] || y[31]) ? SIGN : '0;
        return (mx ^ x_lt_y) ? x : y;
    endfunction

    // The class of x from its value as a real (NaN, the signs and the quiet bit from its bits).
    function automatic class_t class_model(input logic [31:0] x);
        real    r;
        real    m;          // |r|
        class_t c;
        r = to_real(x);
        m = r < 0.0 ? -r : r;
        c = '0;
        if (is_nan(x[30:0])) begin
            c.qnan = x[22];
            c.snan = !x[22];
        end else if (m > 3.4028234663852886e38) begin
            c.pos_inf = r > 0.0;
            c.neg_inf = r < 0.0;
        end else if (m == 0.0) begin
            c.pos_zero = !x[31];
            c.neg_zero = x[31];
        end else if (m < 1.1754943508222875e-38) begin
            c.pos_subnormal = r > 0.0;
            c.neg_subnormal = r < 0.0;
        end else begin
            c.pos_normal = r > 0.0;
            c.neg_normal = r < 0.0;
        end
        return c;
    endfunction

    // A sign injection: x's magnitude, the sign from y.
    function automatic logic [31:0] sgnj_model(input sgnj_op_e o, input logic [31:0] x,
                                               input logic [31:0] y);
        case (o)
            SGNJ_COPY: return y[31] ? x | SIGN : x & ~SIGN;
            SGNJ_NEG:  return y[31] ? x & ~SIGN : x | SIGN;
            default:   return x ^ (y & SIGN);
        endcase
    endfunction

    task automatic fail(input string what, input logic [31:0] got, input logic [31:0] exp);
        $fatal(1, "Fp32Compare %s: a %h b %h: %s got %h, expected %h", name, va, vb, what, got,
               exp);
    endtask

    // A case of function f: its predicate p and NV (quiet or signalling).
    task automatic check_compare(input string f);
        logic got;
        logic got_nv;
        case (f)
            "f32_eq", "f32_eq_signaling":   got = eq;
            "f32_lt", "f32_lt_quiet":       got = lt;
            default:                        got = le;
        endcase
        got_nv = (f == "f32_lt" || f == "f32_le" || f == "f32_eq_signaling") ? unordered : snan;
        if (got !== want[0])
            fail("predicate", 32'(got), 32'(want));
        if ({got_nv, 4'b0} !== want_flags[4:0])
            fail("flags", 32'({got_nv, 4'b0}), 32'(want_flags));
    endtask

    // The models on a pair of f32_lt_quiet.
    task automatic check_others();
        for (int m = 0; m < 2; m++) begin
            max = m[0];
            #1;
            if (min_max_number !== min_max_model(1'b0, max, va, vb, want[0]))
                fail(max ? "max number" : "min number", min_max_number,
                     min_max_model(1'b0, max, va, vb, want[0]));
            if (min_max_nan !== min_max_model(1'b1, max, va, vb, want[0]))
                fail(max ? "max nan" : "min nan", min_max_nan,
                     min_max_model(1'b1, max, va, vb, want[0]));
            if ({nv_number, 4'b0} !== want_flags[4:0] || {nv_nan, 4'b0} !== want_flags[4:0])
                fail("min/max nv", 32'({nv_number, nv_nan}), 32'(want_flags));
        end
        if (class_a !== class_model(va))
            fail("class of a", 32'(class_a), 32'(class_model(va)));
        if (class_b !== class_model(vb))
            fail("class of b", 32'(class_b), 32'(class_model(vb)));
        for (int o = 0; o < 3; o++) begin
            sgnj_op = sgnj_op_e'(o);
            #1;
            if (sgnj !== sgnj_model(sgnj_op, va, vb))
                fail(sgnj_op.name(), sgnj, sgnj_model(sgnj_op, va, vb));
        end
    endtask

    initial begin
        string functions [6];
        functions = '{"f32_eq", "f32_lt", "f32_le", "f32_eq_signaling", "f32_lt_quiet",
                      "f32_le_quiet"};
        if (!$value$plusargs("cases=%s", dir))
            $fatal(1, "Fp32Compare: plusarg +cases=<dir> is missing");
        max     = 1'b0;
        sgnj_op = SGNJ_COPY;
        total   = 0;
        foreach (functions[k]) begin
            name = {dir, "/", functions[k], ".rne"};
            fd   = $fopen(name, "r");
            if (fd == 0)
                $fatal(1, "Fp32Compare: can not open %s", name);
            n = 0;
            while ($fscanf(fd, "%h %h %h %h\n", va, vb, want, want_flags) == 4) begin
                a = va;
                b = vb;
                #1;
                check_compare(functions[k]);
                if (functions[k] == "f32_lt_quiet")
                    check_others();
                n++;
            end
            $fclose(fd);
            if (n == 0)
                $fatal(1, "Fp32Compare: no cases in %s", name);
            total += n;
        end
        $display("PASS: %0d cases", total);
        $finish;
    end
endmodule

/* Test of Fp32DivSqrt against TestFloat: f32_div and f32_sqrt in the five rounding modes.
 *
 * +cases=<dir>: the case files <dir>/<function>.<mode> that testfloat_gen wrote
 * (dc_testfloat_cases, cmake/testfloat.cmake), a line per case in hex: the operands, the fp32
 * result, the flags (SoftFloat's bits, FpPkg::flags_t's order). Every case: the operands at a
 * falling edge with start=1, start=0 at the next; done must come in the 25th clock, busy
 * drop after it; then the result and all five flags must be TestFloat's. The divisor port
 * of a square root gets a signalling NaN, which it must not use. Every file must have
 * cases. Stops at the first mismatch with $fatal.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module TbFp32DivSqrt;
    import Fp32Pkg::*;
    import FpPkg::*;

    localparam int          MODES   = 5;
    localparam int          LATENCY = 25;               // clocks of busy
    localparam logic [31:0] SNAN    = 32'h7fa0_0000;    // b of a square root: not used

    logic        clk;
    logic        rst_n;
    logic        start;
    logic        sqrt;
    fp32_t       a;
    fp32_t       b;
    rm_e         rm;
    logic        busy;
    logic        done;
    fp32_t       result;
    flags_t      flags;

    string       dir;
    string       name;
    integer      fd;
    integer      n;
    integer      total;
    logic [31:0] va;
    logic [31:0] vb;
    logic [31:0] want;
    logic [7:0]  want_flags;

    Fp32DivSqrt u_fp32_div_sqrt(.clk, .rst_n, .start, .sqrt, .a, .b, .rm, .busy, .done,
                                .result, .flags);

    initial clk = 1'b0;
    always #5 clk = ~clk;

    function automatic rm_e mode(input int m);
        case (m)
            0:       return RM_RNE;
            1:       return RM_RTZ;
            2:       return RM_RDN;
            3:       return RM_RUP;
            default: return RM_RMM;
        endcase
    endfunction

    function automatic string suffix(input int m);
        case (m)
            0:       return "rne";
            1:       return "rtz";
            2:       return "rdn";
            3:       return "rup";
            default: return "rmm";
        endcase
    endfunction

    // One operation: start it, count the clocks to done, check the result.
    task automatic run(input logic op_sqrt, input logic [31:0] x, input logic [31:0] y);
        int clocks;
        @(negedge clk);
        sqrt  = op_sqrt;
        a     = x;
        b     = y;
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;
        a     = '0;     // the unit took them
        b     = '0;
        clocks = 1;
        while (!done) begin
            @(negedge clk);
            clocks++;
        end
        @(negedge clk);
        if (clocks != LATENCY || busy)
            $fatal(1, "Fp32DivSqrt %s: done after %0d clocks, busy %b", name, clocks, busy);
        if (result !== want || {3'b0, flags} !== want_flags)
            $fatal(1, "Fp32DivSqrt %s: a %h b %h -> %h flags %b, expected %h flags %b",
                   name, x, y, result, flags, want, want_flags);
    endtask

    task automatic open(input string f, input int m);
        name = {dir, "/", f, ".", suffix(m)};
        fd   = $fopen(name, "r");
        if (fd == 0)
            $fatal(1, "Fp32DivSqrt: can not open %s", name);
        n = 0;
    endtask

    task automatic close();
        $fclose(fd);
        if (n == 0)
            $fatal(1, "Fp32DivSqrt: no cases in %s", name);
        total += n;
    endtask

    initial begin
        if (!$value$plusargs("cases=%s", dir))
            $fatal(1, "Fp32DivSqrt: plusarg +cases=<dir> is missing");
        rst_n = 1'b0;
        start = 1'b0;
        sqrt  = 1'b0;
        a     = '0;
        b     = '0;
        rm    = RM_RNE;
        repeat (2) @(negedge clk);
        rst_n = 1'b1;
        total = 0;
        for (int m = 0; m < MODES; m++) begin
            rm = mode(m);
            open("f32_div", m);
            while ($fscanf(fd, "%h %h %h %h\n", va, vb, want, want_flags) == 4) begin
                run(1'b0, va, vb);
                n++;
            end
            close();
            open("f32_sqrt", m);
            while ($fscanf(fd, "%h %h %h\n", va, want, want_flags) == 3) begin
                run(1'b1, va, SNAN);
                n++;
            end
            close();
        end
        $display("PASS: %0d cases", total);
        $finish;
    end
endmodule

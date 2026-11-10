/* Test of Fp32Fma against TestFloat: f32_mulAdd as all four fused forms, f32_add, f32_sub
 * and f32_mul, in the five rounding modes.
 *
 * +cases=<dir>: the case files <dir>/<function>.<mode> that testfloat_gen wrote
 * (dc_testfloat_cases, cmake/testfloat.cmake), a line per case in hex: the operands, the
 * fp32 result, the flags (SoftFloat's bits, FpPkg::flags_t's order). A case of f32_mulAdd
 * (a * b + c = z) is checked four times, the operand signs flipped so that every form gives
 * z: MADD(a, b, c), MSUB(a, b, -c), NMSUB(-a, b, c), NMADD(-a, b, -c) (flipping a NaN's sign
 * keeps it a NaN of its kind). ADD, SUB and MUL get c = a signalling NaN, which they must
 * not use (no NV from it). The result and all five flags must be TestFloat's. Every file
 * must have cases. Stops at the first mismatch with $fatal.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module TbFp32Fma;
    import Fp32Pkg::*;
    import FpPkg::*;

    localparam int          MODES = 5;
    localparam logic [31:0] SIGN  = 32'h8000_0000;
    localparam logic [31:0] SNAN  = 32'h7fa0_0000;  // c of ADD, SUB, MUL: not used

    fp32_t       a;
    fp32_t       b;
    fp32_t       c;
    fma_op_e     op;
    rm_e         rm;
    fp32_t       result;
    flags_t      flags;

    string       dir;
    string       name;
    integer      fd;
    integer      n;             // cases of a file
    integer      total;
    logic [31:0] va;            // a case: the operands, the result, the flags
    logic [31:0] vb;
    logic [31:0] vc;
    logic [31:0] want;
    logic [7:0]  want_flags;

    Fp32Fma u_fp32_fma(.a, .b, .c, .op, .rm, .result, .flags);

    // Mode m (0 to 4) and the suffix of its case file.
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

    // Operation o on x, y, z must give want and want_flags.
    task automatic check(input fma_op_e o, input logic [31:0] x, input logic [31:0] y,
                         input logic [31:0] z);
        op = o;
        a  = x;
        b  = y;
        c  = z;
        #1;
        if (result !== want || {3'b0, flags} !== want_flags)
            $fatal(1, "Fp32Fma %s %s: a %h b %h c %h -> %h flags %b, expected %h flags %b",
                   name, o.name(), x, y, z, result, flags, want, want_flags);
    endtask

    // Open the case file of function f in mode m.
    task automatic open(input string f, input int m);
        name = {dir, "/", f, ".", suffix(m)};
        fd   = $fopen(name, "r");
        if (fd == 0)
            $fatal(1, "Fp32Fma: can not open %s", name);
        n = 0;
    endtask

    task automatic close();
        $fclose(fd);
        if (n == 0)
            $fatal(1, "Fp32Fma: no cases in %s", name);
        total += n;
    endtask

    initial begin
        if (!$value$plusargs("cases=%s", dir))
            $fatal(1, "Fp32Fma: plusarg +cases=<dir> is missing");
        total = 0;
        for (int m = 0; m < MODES; m++) begin
            rm = mode(m);
            open("f32_mulAdd", m);
            while ($fscanf(fd, "%h %h %h %h %h\n", va, vb, vc, want, want_flags) == 5) begin
                check(FMA_MADD, va, vb, vc);
                check(FMA_MSUB, va, vb, vc ^ SIGN);
                check(FMA_NMSUB, va ^ SIGN, vb, vc);
                check(FMA_NMADD, va ^ SIGN, vb, vc ^ SIGN);
                n++;
            end
            close();
            open("f32_add", m);
            while ($fscanf(fd, "%h %h %h %h\n", va, vb, want, want_flags) == 4) begin
                check(FMA_ADD, va, vb, SNAN);
                n++;
            end
            close();
            open("f32_sub", m);
            while ($fscanf(fd, "%h %h %h %h\n", va, vb, want, want_flags) == 4) begin
                check(FMA_SUB, va, vb, SNAN);
                n++;
            end
            close();
            open("f32_mul", m);
            while ($fscanf(fd, "%h %h %h %h\n", va, vb, want, want_flags) == 4) begin
                check(FMA_MUL, va, vb, SNAN);
                n++;
            end
            close();
        end
        $display("PASS: %0d cases", total);
        $finish;
    end
endmodule

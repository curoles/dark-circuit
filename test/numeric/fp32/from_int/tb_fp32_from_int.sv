/* Test of Fp32FromInt against TestFloat: i32_to_f32 and ui32_to_f32 in the five rounding
 * modes.
 *
 * +cases=<dir>: the case files <dir>/i32_to_f32.<mode> and <dir>/ui32_to_f32.<mode>, <mode>
 * rne, rtz, rdn, rup, rmm, that testfloat_gen wrote (dc_testfloat_cases,
 * cmake/testfloat.cmake), a line per case in hex: the integer, the fp32 result, the flags
 * (SoftFloat's bits, FpPkg::flags_t's order). Every case goes to Fp32FromInt with its
 * file's signedness and mode; the result and all five flags must be TestFloat's. Every file
 * must have cases. Stops at the first mismatch with $fatal.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module TbFp32FromInt;
    import Fp32Pkg::*;
    import FpPkg::*;

    localparam int MODES = 5;

    logic [31:0] a;
    logic        is_signed;
    rm_e         rm;
    fp32_t       result;
    flags_t      flags;

    string       dir;
    string       name;
    integer      fd;
    integer      n;             // cases of a file
    integer      total;
    logic [31:0] in;            // a case: the integer, the result, the flags
    logic [31:0] want;
    logic [7:0]  want_flags;

    Fp32FromInt u_fp32_from_int(.a, .is_signed, .rm, .result, .flags);

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

    initial begin
        if (!$value$plusargs("cases=%s", dir))
            $fatal(1, "Fp32FromInt: plusarg +cases=<dir> is missing");
        total = 0;
        for (int s = 1; s >= 0; s--)
            for (int m = 0; m < MODES; m++) begin
                is_signed = s[0];
                rm        = mode(m);
                name      = {dir, is_signed ? "/i32_to_f32." : "/ui32_to_f32.", suffix(m)};
                fd        = $fopen(name, "r");
                if (fd == 0)
                    $fatal(1, "Fp32FromInt: can not open %s", name);
                n = 0;
                while ($fscanf(fd, "%h %h %h\n", in, want, want_flags) == 3) begin
                    a = in;
                    #1;
                    if (result !== want || {3'b0, flags} !== want_flags)
                        $fatal(1, "Fp32FromInt %s: %h -> %h flags %b, expected %h flags %b",
                               name, a, result, flags, want, want_flags);
                    n++;
                end
                $fclose(fd);
                if (n == 0)
                    $fatal(1, "Fp32FromInt: no cases in %s", name);
                total += n;
            end
        $display("PASS: %0d cases", total);
        $finish;
    end
endmodule

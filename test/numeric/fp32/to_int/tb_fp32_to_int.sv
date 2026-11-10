/* Test of Fp32ToInt against TestFloat: f32_to_i32 and f32_to_ui32 in the five rounding modes,
 * with both rules for an invalid conversion.
 *
 * +cases=<dir>: the case files <dir>/<function>.<mode> that testfloat_gen wrote with -exact
 * (an inexact result flags NX, as RISC-V's FCVT does; dc_testfloat_cases EXACT,
 * cmake/testfloat.cmake), a line per case in hex: the fp32, the integer, the flags. TestFloat's
 * RISC-V specialization gives RISC-V's integers for invalid conversions: TOINT_RISCV must
 * give them; TOINT_ARM the same but 0 for a NaN. The flags must be TestFloat's for both.
 * Every file must have cases. Stops at the first mismatch with $fatal.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module TbFp32ToInt;
    import Fp32Pkg::*;
    import FpPkg::*;

    localparam int MODES = 5;

    fp32_t       x;
    logic        is_signed;
    rm_e         rm;
    logic [31:0] riscv_result;
    flags_t      riscv_flags;
    logic [31:0] arm_result;
    flags_t      arm_flags;

    string       dir;
    string       name;
    integer      fd;
    integer      n;
    integer      total;
    logic [31:0] vx;
    logic [31:0] want;
    logic [7:0]  want_flags;
    logic [31:0] want_arm;      // Arm's integer: 0 for a NaN

    Fp32ToInt #(.INVALID(TOINT_RISCV)) u_to_int_riscv(
        .x, .is_signed, .rm, .result(riscv_result), .flags(riscv_flags));
    Fp32ToInt #(.INVALID(TOINT_ARM)) u_to_int_arm(
        .x, .is_signed, .rm, .result(arm_result), .flags(arm_flags));

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

    // v (an fp32 but its sign) is a NaN: exponent field all ones, fraction not 0.
    function automatic logic is_nan(input logic [30:0] v);
        return v[30:23] == '1 && v[22:0] != '0;
    endfunction

    initial begin
        if (!$value$plusargs("cases=%s", dir))
            $fatal(1, "Fp32ToInt: plusarg +cases=<dir> is missing");
        total = 0;
        for (int s = 1; s >= 0; s--)
            for (int m = 0; m < MODES; m++) begin
                is_signed = s[0];
                rm        = mode(m);
                name      = {dir, is_signed ? "/f32_to_i32." : "/f32_to_ui32.", suffix(m)};
                fd        = $fopen(name, "r");
                if (fd == 0)
                    $fatal(1, "Fp32ToInt: can not open %s", name);
                n = 0;
                while ($fscanf(fd, "%h %h %h\n", vx, want, want_flags) == 3) begin
                    x = vx;
                    #1;
                    want_arm = is_nan(vx[30:0]) ? '0 : want;
                    if (riscv_result !== want || {3'b0, riscv_flags} !== want_flags)
                        $fatal(1, "Fp32ToInt %s RISCV: %h -> %h flags %b, expected %h flags %b",
                               name, vx, riscv_result, riscv_flags, want, want_flags);
                    if (arm_result !== want_arm || {3'b0, arm_flags} !== want_flags)
                        $fatal(1, "Fp32ToInt %s ARM: %h -> %h flags %b, expected %h flags %b",
                               name, vx, arm_result, arm_flags, want_arm, want_flags);
                    n++;
                end
                $fclose(fd);
                if (n == 0)
                    $fatal(1, "Fp32ToInt: no cases in %s", name);
                total += n;
            end
        $display("PASS: %0d cases", total);
        $finish;
    end
endmodule

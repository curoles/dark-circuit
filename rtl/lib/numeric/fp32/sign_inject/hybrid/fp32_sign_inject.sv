/* Fp32 sign injection: a's magnitude with a sign from b (RISC-V FSGNJ.S, FSGNJN.S,
 * FSGNJX.S; with b = a they are a move, a negation and an absolute value), hybrid.
 *
 * op (FpPkg::sgnj_op_e): SGNJ_COPY b's sign (IEEE copySign), SGNJ_NEG its inverse, SGNJ_XOR
 * a's sign xor b's. No arithmetic, no exception, a NaN keeps its payload (IEEE: sign
 * operations are not arithmetic). Hybrid (AGENTS.md): glue only.
 *
 *   a[30:0] ------------------------------> result[30:0]
 *   a.sign, b.sign, op --> the new sign --> result[31]
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module Fp32SignInject import Fp32Pkg::*, FpPkg::*; (
    input  fp32_t    a,
    // Only b's sign is used.
    /* verilator lint_off UNUSEDSIGNAL */
    input  fp32_t    b,
    /* verilator lint_on UNUSEDSIGNAL */
    input  sgnj_op_e op,
    output fp32_t    result
);
    logic sign;

    assign sign   = op == SGNJ_COPY ? b.sign :
                    op == SGNJ_NEG  ? !b.sign
                                    : a.sign ^ b.sign;      // SGNJ_XOR
    assign result = {sign, a[$bits(fp32_t)-2:0]};

endmodule

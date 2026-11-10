/* Fp32 unpack: an fp32 taken apart into sign, exponent and significand, with its class,
 * hybrid.
 *
 * exp is the biased exponent the significand counts with: a subnormal (and a zero) has an
 * exponent field of 0 but counts with exponent 1 (0.fraction * 2^-126), so exp is 1 and
 * sig's hidden bit 0; a normal number keeps its field and gets the hidden 1. The class:
 * zero, subnormal, infinity, NaN and signalling NaN (a NaN whose quiet bit, the top of the
 * fraction, is 0). For an infinity or a NaN, exp and sig are not used. Hybrid (AGENTS.md):
 * no wide arithmetic, only glue (reductions of the 8 exponent and 23 fraction bits).
 *
 *   x --> exponent field 0? all ones? fraction 0? --> class
 *     --> {field, or 1 when 0}, {hidden bit, fraction} --> exp, sig
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module Fp32Unpack import Fp32Pkg::*; (
    input  fp32_t          x,
    output fp32_unpacked_t u
);
    logic exp_zero;     // exponent field 0: a zero or a subnormal
    logic exp_ones;     // exponent field all ones: an infinity or a NaN
    logic frac_zero;    // fraction 0

    assign exp_zero  = ~|x.exp;
    assign exp_ones  = &x.exp;
    assign frac_zero = ~|x.mant;

    assign u.sign      = x.sign;
    assign u.exp       = {x.exp[FP32_EXP_WIDTH-1:1], x.exp[0] || exp_zero};
    assign u.sig       = {!exp_zero, x.mant};
    assign u.zero      = exp_zero && frac_zero;
    assign u.subnormal = exp_zero && !frac_zero;
    assign u.inf       = exp_ones && frac_zero;
    assign u.nan       = exp_ones && !frac_zero;
    assign u.snan      = exp_ones && !frac_zero && !x.mant[FP32_MANT_WIDTH-1];

endmodule

/* Fp32 combinational multiplier: IEEE-754 single precision a * b, behavioral.
 *
 * Multiplies the 24-bit mantissas (hidden 1 added), adds the exponents minus the bias
 * 127 and normalizes by one bit; the mantissa is truncated, not rounded. An input with
 * exponent 0 (zero or subnormal) gives 0. Infinity, NaN and exponent overflow or
 * underflow are not handled.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module Fp32CombMultiplier import Fp32Pkg::*; (
    input  fp32_t a,        // operands
    input  fp32_t b,
    output fp32_t result    // a * b
);
    fp32_sig_t  a_sig;      // significands: hidden 1 and fraction
    fp32_sig_t  b_sig;
    // Product of the significands, in [1, 4); its low bits are dropped: the result is
    // truncated, not rounded.
    /* verilator lint_off UNUSEDSIGNAL */
    fp32_prod_t prod;
    /* verilator lint_on UNUSEDSIGNAL */
    fp32_exp_t  exp_sum;    // a.exp + b.exp - bias, mod 256: overflow is not handled
    logic       zero;       // an operand has exponent 0 (zero or subnormal)
    logic       sign;       // sign of the product
    fp32_exp_t  exp;        // exponent of the normalized product
    fp32_mant_t mant;       // its fraction, truncated

    assign a_sig   = {1'b1, a.mant};
    assign b_sig   = {1'b1, b.mant};
    assign prod    = a_sig * b_sig;
    assign exp_sum = a.exp + b.exp - FP32_BIAS;
    assign zero    = a.exp == 0 || b.exp == 0;

    // A product in [2, 4) (its top bit set) shifts right by one: exponent + 1.
    // The fraction is prod[46:24], else prod[45:23].
    assign sign   = a.sign ^ b.sign;
    assign exp    = prod[FP32_PROD_MSB] ? exp_sum + 1'b1 : exp_sum;
    assign mant   = prod[FP32_PROD_MSB] ? prod[FP32_PROD_MSB-1 -: FP32_MANT_WIDTH]
                                        : prod[FP32_PROD_MSB-2 -: FP32_MANT_WIDTH];
    assign result = zero ? '0 : {sign, exp, mant};

endmodule

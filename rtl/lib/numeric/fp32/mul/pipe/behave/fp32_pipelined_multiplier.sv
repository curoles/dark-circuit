/* Fp32 pipelined multiplier: IEEE-754 single precision a * b in three stages, behavioral.
 *
 * The arithmetic of Fp32CombMultiplier in three register stages: mantissa product and
 * exponents, then the normalized result, then the output; result is the product of a
 * and b of three rising edges before. Only the zero flags and result are reset.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module Fp32PipelinedMultiplier import Fp32Pkg::*; (
    input  wire   clk,
    input  wire   rst_n,    // synchronous reset, active low: zero flags and result
    input  fp32_t a,        // operands
    input  fp32_t b,
    output fp32_t result    // a * b of three rising edges before
);
    typedef struct packed {
        fp32_prod_t prod;   // product of the significands, in [1, 4)
        logic       sign;   // sign of the product
        fp32_exp_t  a_exp;  // exponents of the operands
        fp32_exp_t  b_exp;
    } stage1_t;

    fp32_sig_t  a_sig;      // significands: hidden 1 and fraction
    fp32_sig_t  b_sig;
    fp32_prod_t prod;       // a_sig * b_sig
    stage1_t    s1_d;       // into the stage 1 register
    stage1_t    s1_q;
    // The product in stage 1, a plain vector: Icarus 13 crashes on an indexed part-select
    // of a struct field. Its low bits are dropped: truncated, not rounded.
    /* verilator lint_off UNUSEDSIGNAL */
    fp32_prod_t s1_prod;
    /* verilator lint_on UNUSEDSIGNAL */
    logic       s1_zero_q;  // an operand in stage 1 has exponent 0
    fp32_exp_t  exp_sum;    // exponents summed minus bias, mod 256: overflow not handled
    fp32_exp_t  s2_exp;     // exponent of the normalized product
    fp32_mant_t s2_mant;    // its fraction, truncated
    fp32_t      s2_q;       // the normalized product
    logic       s2_zero_q;  // an operand in stage 2 has exponent 0

    // Stage 1: product of the significands, sign and exponents.
    assign a_sig = {1'b1, a.mant};
    assign b_sig = {1'b1, b.mant};
    assign prod  = a_sig * b_sig;
    assign s1_d  = {prod, a.sign ^ b.sign, a.exp, b.exp};

    always_ff @(posedge clk) s1_q <= s1_d;      // data: not reset
    always_ff @(posedge clk)
        if (!rst_n) s1_zero_q <= 1'b0;
        else        s1_zero_q <= a.exp == 0 || b.exp == 0;

    // Stage 2: normalize; a product in [2, 4) (its top bit set) shifts right by one:
    // exponent + 1. The fraction is prod[46:24], else prod[45:23].
    assign s1_prod = s1_q.prod;
    assign exp_sum = s1_q.a_exp + s1_q.b_exp - FP32_BIAS;
    assign s2_exp  = s1_prod[FP32_PROD_MSB] ? exp_sum + 1'b1 : exp_sum;
    assign s2_mant = s1_prod[FP32_PROD_MSB] ? s1_prod[FP32_PROD_MSB-1 -: FP32_MANT_WIDTH]
                                            : s1_prod[FP32_PROD_MSB-2 -: FP32_MANT_WIDTH];

    always_ff @(posedge clk) s2_q <= {s1_q.sign, s2_exp, s2_mant};  // data: not reset
    always_ff @(posedge clk)
        if (!rst_n) s2_zero_q <= 1'b0;
        else        s2_zero_q <= s1_zero_q;

    // Stage 3: the output register.
    always_ff @(posedge clk)
        if (!rst_n) result <= '0;
        else        result <= s2_zero_q ? '0 : s2_q;

endmodule

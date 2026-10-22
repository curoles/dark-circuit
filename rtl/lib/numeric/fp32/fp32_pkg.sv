/* Fp32 package: the IEEE-754 single precision format.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
package Fp32Pkg;

    localparam int FP32_EXP_WIDTH  = 8;                         // exponent bits
    localparam int FP32_MANT_WIDTH = 23;                        // fraction bits
    // 47: the top bit of a product of two significands, set when it is in [2, 4).
    localparam int FP32_PROD_MSB   = 2 * FP32_MANT_WIDTH + 1;

    typedef logic [FP32_EXP_WIDTH-1:0]  fp32_exp_t;     // biased exponent
    typedef logic [FP32_MANT_WIDTH-1:0] fp32_mant_t;    // fraction after the hidden 1
    typedef logic [FP32_MANT_WIDTH:0]   fp32_sig_t;     // significand: hidden 1 and fraction
    typedef logic [FP32_PROD_MSB:0]     fp32_prod_t;    // product of two significands

    localparam fp32_exp_t FP32_BIAS = 8'd127;           // exponent bias

    // Value (-1)^sign * 1.mant * 2^(exp - 127) for exp 1..254.
    typedef struct packed {
        logic       sign;   // 1: negative
        fp32_exp_t  exp;    // biased exponent
        fp32_mant_t mant;   // fraction after the hidden 1
    } fp32_t;

endpackage

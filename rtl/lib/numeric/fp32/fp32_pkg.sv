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

    // Constants: a design uses some of them.
    /* verilator lint_off UNUSEDPARAM */
    localparam fp32_t FP32_ONE = {1'b0, FP32_BIAS, {FP32_MANT_WIDTH{1'b0}}};  // 1.0
    // The default NaN, every NaN result: no payload (RISC-V's canonical NaN, 0x7fc00000).
    localparam fp32_t FP32_DEFAULT_NAN = {1'b0, {FP32_EXP_WIDTH{1'b1}}, 1'b1,
                                          {(FP32_MANT_WIDTH - 1){1'b0}}};
    /* verilator lint_on UNUSEDPARAM */

    // An fp32 taken apart (Fp32Unpack): (-1)^sign * 0.fraction or 1.fraction (sig) *
    // 2^(exp - 127), with its class.
    typedef struct packed {
        logic       sign;
        fp32_exp_t  exp;        // biased exponent sig counts with: 1 for a subnormal, a zero
        fp32_sig_t  sig;        // the hidden bit (0 for a subnormal, a zero), the fraction
        logic       zero;
        logic       subnormal;
        logic       inf;
        logic       nan;
        logic       snan;       // a signalling NaN: its quiet bit is 0
    } fp32_unpacked_t;

endpackage

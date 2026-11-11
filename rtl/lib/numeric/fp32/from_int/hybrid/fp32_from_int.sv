/* Fp32 from integer: a 32-bit signed or unsigned integer to the nearest fp32 by a rounding
 * mode (RISC-V FCVT.S.W, FCVT.S.WU), hybrid.
 *
 * The magnitude (2^31 for the most negative int32: ~a + 1) is normalized by the index of
 * its top 1 and the exponent is 127 + index. The top 1 is searched (PriorityEncoder) in
 * ones = a, or ~a for a negative a (the magnitude less one), while the increment makes the
 * magnitude: so the search does not wait for the increment (kb
 * rtl/lib/numeric/fp32/design). The magnitude's top 1 is at ones' index, or one above when
 * the increment carries up to it (ones = 2^k - 1, the magnitude 2^k): shifted left by
 * 31 - index, which is ~index in 5 bits, into 33 bits, the top 1 lands in bit 31, or in bit
 * 32 (carry): then the significand is taken one bit higher and the exponent is one more.
 * Fp32Round keeps 24 of the 32 bits; a magnitude above 2^24 may be inexact (NX). No
 * overflow (2^32 is far below the largest fp32), no underflow, no NV; 0 gives +0. Hybrid
 * (AGENTS.md): the increment, the search, the shift, the sum and the selects are library
 * blocks, parts and gates; the inversion is an operator.
 *
 *   a --> ones (a ^ neg) --> Incr --> Mux2 (neg = is_signed & a[31]) --> mag
 *              +--> PriorityEncoder --> top
 *   mag, top --> BarrelShifter mag << ~top (33 bits) --> Mux2 (carry: bit 32) --> sig
 *   top, carry --> BrentKungAdder 127 + top + carry --> exp
 *   rm --> Fp32Round (sig 32 bits, exp) --> result, flags
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module Fp32FromInt import Fp32Pkg::*, FpPkg::*; (
    input  wire [31:0] a,           // the integer
    input  wire        is_signed,   // 1: a is an int32 (FCVT.S.W), 0: a uint32 (FCVT.S.WU)
    input  rm_e        rm,          // rounding mode
    output fp32_t      result,
    output flags_t     flags        // NX; the others 0
);
    localparam int EXP_WIDTH = 10;

    logic                 neg;      // a is negative
    logic [31:0]          ones;     // a, or ~a for a negative a: the magnitude less neg
    logic [31:0]          ones_inc; // ones + 1: -a for a negative a
    logic [31:0]          mag;      // |a|
    logic [4:0]           top;      // index of the top 1 of ones, 0 when ones is 0
    logic [32:0]          wide;     // mag << 31 - top: its top 1 in bit 31, or 32
    logic                 carry;    // in bit 32: mag is 2^(top + 1)
    logic [31:0]          sig;      // mag normalized: its top 1 in bit 31
    logic [EXP_WIDTH-1:0] exp;      // the biased exponent of that bit, 127 + top + carry
    // Not used: the carries out (ones of a negative a is below 2^31; 128 + 31 fits) and the
    // encoder's valid (ones = 0 is a = 0, sig 0, or a = -1, mag 1 in bit 0: index 0 too).
    /* verilator lint_off UNUSEDSIGNAL */
    logic                 neg_co;
    logic                 exp_co;
    logic                 nonzero;
    /* verilator lint_on UNUSEDSIGNAL */

    assign neg  = is_signed && a[31];
    assign ones = a ^ {32{neg}};

    // @kb: rtl/lib/numeric/fp32/design
    Incr #(.WIDTH(32)) u_incr_neg(.in(ones), .out(ones_inc), .co(neg_co));
    Mux2 #(.WIDTH(32)) u_mux2_mag(.in0(ones), .in1(ones_inc), .sel(neg), .out(mag));

    PriorityEncoder #(.SIZE(5)) u_priority_encoder(.in(ones), .out(top), .valid(nonzero));

    BarrelShifter #(.WIDTH(33)) u_shifter(
        .in({1'b0, mag}), .shift_in_bit(1'b0), .shift({1'b0, ~top}), .shift_rotate(1'b1),
        .left_right(1'b1), .out(wide));
    assign carry = wide[32];
    Mux2 #(.WIDTH(32)) u_mux2_sig(.in0(wide[31:0]), .in1(wide[32:1]), .sel(carry), .out(sig));
    BrentKungAdder #(.WIDTH(EXP_WIDTH)) u_adder_exp(
        .in1(EXP_WIDTH'(FP32_BIAS)), .in2(EXP_WIDTH'(top)), .ci(carry), .co(exp_co),
        .sum(exp));

    Fp32Round #(.SIG_WIDTH(32), .EXP_WIDTH(EXP_WIDTH)) u_round(
        .sign(neg), .exp, .sig, .rm, .result, .flags);

endmodule

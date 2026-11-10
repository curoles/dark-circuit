/* Fp32 from integer: a 32-bit signed or unsigned integer to the nearest fp32 by a rounding
 * mode (RISC-V FCVT.S.W, FCVT.S.WU), hybrid.
 *
 * The magnitude (2^31 for the most negative int32: ~a + 1) is normalized by the index of
 * its top 1 (PriorityEncoder): shifted left by 31 - index, which is ~index in 5 bits, and
 * the exponent is 127 + index. Fp32Round keeps 24 of the 32 bits; a magnitude above 2^24
 * may be inexact (NX). No overflow (2^32 is far below the largest fp32), no underflow, no
 * NV; 0 gives +0. Hybrid (AGENTS.md): the increment, the shift, the sum and the select
 * are library blocks, parts and gates; the inversions are operators.
 *
 *   a --> ~a --> Incr --> Mux2 (neg = is_signed & a[31]) --> mag
 *   +-----------------------^                                  |
 *   mag --> PriorityEncoder --> top --> BarrelShifter mag << ~top --> sig
 *                                 +---> BrentKungAdder 127 + top --> exp
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
    logic [31:0]          a_neg;    // -a = ~a + 1
    logic [31:0]          mag;      // |a|
    logic [4:0]           top;      // index of the top 1 of mag, 0 when mag is 0
    logic [31:0]          sig;      // mag normalized: its top 1 in bit 31
    logic [EXP_WIDTH-1:0] exp;      // the biased exponent of that bit, 127 + top
    // Not used: the carries out (-0 is 0; 127 + 31 fits) and the encoder's valid (mag = 0
    // gives sig = 0, a zero for Fp32Round).
    /* verilator lint_off UNUSEDSIGNAL */
    logic                 neg_co;
    logic                 exp_co;
    logic                 nonzero;
    /* verilator lint_on UNUSEDSIGNAL */

    assign neg = is_signed && a[31];

    Incr #(.WIDTH(32)) u_incr_neg(.in(~a), .out(a_neg), .co(neg_co));
    Mux2 #(.WIDTH(32)) u_mux2_mag(.in0(a), .in1(a_neg), .sel(neg), .out(mag));

    PriorityEncoder #(.SIZE(5)) u_priority_encoder(.in(mag), .out(top), .valid(nonzero));

    BarrelShifter #(.WIDTH(32)) u_shifter(
        .in(mag), .shift_in_bit(1'b0), .shift(~top), .shift_rotate(1'b1), .left_right(1'b1),
        .out(sig));
    BrentKungAdder #(.WIDTH(EXP_WIDTH)) u_adder_exp(
        .in1(EXP_WIDTH'(FP32_BIAS)), .in2(EXP_WIDTH'(top)), .ci(1'b0), .co(exp_co),
        .sum(exp));

    Fp32Round #(.SIG_WIDTH(32), .EXP_WIDTH(EXP_WIDTH)) u_round(
        .sign(neg), .exp, .sig, .rm, .result, .flags);

endmodule

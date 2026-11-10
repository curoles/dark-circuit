/* Fp32 rounding: a wider significand with an exponent of any range to an fp32 and its
 * exception flags, hybrid.
 *
 * The value is (-1)^sign * sig * 2^(exp - 127 - (SIG_WIDTH - 1)): sig's top bit is the
 * integer bit and exp its biased exponent, signed, so a value below the normal range
 * (exp < 1) or above it (exp > 254) comes in as it is. sig is normalized (top bit 1) by the
 * caller, or 0: a zero of its sign (exp not used, no flags). The operation (a conversion,
 * the FMA) computes the exact value, or enough of it: bits below the 24 kept and a sticky
 * bit (the OR of everything lower) as sig's last bit.
 *  - Below the normal range the value is shifted right to exponent 1 first, by 1 - exp: a
 *    subnormal; the bits shifted out are ORed into sig's last bit (all of sig when the
 *    shift is SIG_WIDTH or more).
 *  - Guard is the bit below the 24 kept (the integer bit and 23 fraction bits), sticky the
 *    OR of the bits below it; inexact = guard | sticky.
 *  - The word {exponent field, fraction} is the exponent (0 below the normal range) and
 *    the 23 fraction bits; rm decides whether it is incremented. The carry goes from the
 *    fraction into the exponent: 1.1...1 becomes the next power of 2, and a subnormal
 *    becomes 2^-126, the smallest normal number (its integer bit, 0, became 1). Incr makes
 *    the incremented word while the increment is decided; a Mux2 picks.
 *  - Overflow, a rounded exponent field of 255 or more: infinity, or the largest finite
 *    number in the modes that round toward zero there (RTZ; RDN for a positive, RUP for a
 *    negative value); flags OF and NX.
 *  - Underflow: tiny after rounding (RISC-V's choice of IEEE 754's two) and inexact. Tiny
 *    after rounding: below 2^-126 once rounded to 24 bits with an unbounded exponent, so
 *    exp < 0, or exp = 0 and sig does not round up to 2.0 (then the value is 2^-126).
 * NV and DZ are 0: the operation decides them. rm encodings other than FpPkg's five do not
 * come (a core traps them); they round as RTZ.
 * Hybrid (AGENTS.md): the shifts, the subtraction, the increment, the compare and the wide
 * selects are library blocks, parts and gates; the narrow glue is operators.
 *
 *   exp --> BrentKungAdder 1 - exp --> CmpGe (>= SIG_WIDTH: all of sig is sticky)
 *                   |
 *   sig --> BarrelShifter >> --> sig_d: kept 24 | guard | sticky
 *     +---> BarrelShifter (ones << n) --> lost bits --> jam into sig_d's last bit
 *                                         |
 *   {exponent field, fraction} --> Incr --> Mux2 (inc: rm, sign, lsb, guard, sticky)
 *                                             |
 *                     CmpGe 255 --> overflow --> Mux4 (normal, overflow value, zero)
 *                                                  --> result; flags
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
`include "dark_circuit_assert.svh"

module Fp32Round import Fp32Pkg::*, FpPkg::*; #(
    parameter int SIG_WIDTH = 26,   // bits of sig: 24 kept, a guard bit, then sticky bits
    parameter int EXP_WIDTH = 10    // bits of exp, signed
)(
    input  wire                        sign,
    input  wire signed [EXP_WIDTH-1:0] exp,     // biased exponent of sig's top bit
    input  wire        [SIG_WIDTH-1:0] sig,     // normalized significand, or 0
    input  rm_e                        rm,      // rounding mode
    output fp32_t                      result,
    output flags_t                     flags    // OF, UF, NX; NV and DZ 0
);
    localparam int W    = SIG_WIDTH;
    localparam int SW   = $clog2(W);                    // bits of a shift by less than W
    localparam int KEPT = FP32_MANT_WIDTH + 1;          // 24: the integer bit and the fraction
    localparam int WORD = EXP_WIDTH + FP32_MANT_WIDTH;  // {exponent field, fraction}
    localparam int FP   = FP32_EXP_WIDTH + FP32_MANT_WIDTH;     // 31: an fp32 but its sign

    // A guard bit and a sticky bit at least; room for every exponent above and below.
    `DC_STATIC_ASSERT(a_widths, SIG_WIDTH >= KEPT + 2 && EXP_WIDTH > FP32_EXP_WIDTH)

    // @kb: rtl/lib/numeric/fp32/design
    // Round up (increment the kept bits): the mode, the sign, the last kept bit, guard and
    // sticky.
    function automatic logic round_up(input rm_e m, input logic s, input logic lsb,
                                      input logic guard, input logic sticky);
        case (m)
            RM_RNE:  return guard && (sticky || lsb);
            RM_RDN:  return s && (guard || sticky);
            RM_RUP:  return !s && (guard || sticky);
            RM_RMM:  return guard;
            default: return 1'b0;                   // RTZ
        endcase
    endfunction

    logic                 zero;         // sig = 0
    logic                 below;        // exp < 1: below the normal range
    logic [EXP_WIDTH-1:0] shift;        // 1 - exp: the shift to exponent 1 when below
    // Its carry out: not used (the shift is read only below the normal range).
    /* verilator lint_off UNUSEDSIGNAL */
    logic                 shift_co;
    /* verilator lint_on UNUSEDSIGNAL */
    logic                 shift_all;    // the shift is W or more: all of sig is sticky
    logic [W-1:0]         shifted;      // sig >> shift
    logic [W-1:0]         keep_mask;    // ones << shift: the bits that stay
    logic                 lost;         // a 1 shifted out
    logic [W-1:0]         sig_d;        // sig at exponent 1 with the lost bits jammed
    logic [W-1:0]         sig_r;        // the significand rounded: sig, or sig_d below
    logic [FP32_MANT_WIDTH-1:0] frac;   // the kept fraction (the integer bit is in the field)
    logic                 guard;
    logic                 sticky;
    logic                 inexact;
    logic                 inc;          // round up
    logic [WORD-1:0]      word;         // {exponent field, fraction} before rounding
    logic [WORD-1:0]      word_inc;     // word + 1
    // Its carry out: never (the exponent field has room above 255).
    /* verilator lint_off UNUSEDSIGNAL */
    logic                 word_co;
    /* verilator lint_on UNUSEDSIGNAL */
    logic [WORD-1:0]      word_r;       // the word rounded
    logic                 overflow;     // its exponent field is 255 or more
    logic                 to_inf;       // overflow gives infinity, else the largest finite
    logic [FP-1:0]        ovf_value;    // infinity or the largest finite, without the sign
    logic [FP-1:0]        magnitude;    // the result without its sign
    logic                 carry_n;      // sig rounded at 24 bits, unshifted, becomes 2.0
    logic                 tiny;         // tiny after rounding

    assign zero  = ~|sig;
    assign below = exp[EXP_WIDTH-1] || ~|exp;

    // 1 - exp = ~exp + 2.
    BrentKungAdder #(.WIDTH(EXP_WIDTH)) u_adder_shift(
        .in1(~exp), .in2(EXP_WIDTH'(1)), .ci(1'b1), .co(shift_co), .sum(shift));
    CmpGe #(.WIDTH(EXP_WIDTH)) u_cmp_ge_shift_all(
        .in1(shift), .in2(EXP_WIDTH'(W)), .ge(shift_all));

    BarrelShifter #(.WIDTH(W)) u_shifter_sig(
        .in(sig), .shift_in_bit(1'b0), .shift(shift[SW-1:0]), .shift_rotate(1'b1),
        .left_right(1'b0), .out(shifted));
    BarrelShifter #(.WIDTH(W)) u_shifter_mask(
        .in({W{1'b1}}), .shift_in_bit(1'b0), .shift(shift[SW-1:0]), .shift_rotate(1'b1),
        .left_right(1'b1), .out(keep_mask));

    assign lost  = |(sig & ~keep_mask);
    assign sig_d = shift_all ? {{(W - 1){1'b0}}, !zero}
                             : {shifted[W-1:1], shifted[0] || lost};

    Mux2 #(.WIDTH(W)) u_mux2_sig(.in0(sig), .in1(sig_d), .sel(below), .out(sig_r));

    assign frac    = sig_r[W-2 -: FP32_MANT_WIDTH];
    assign guard   = sig_r[W-1-KEPT];
    assign sticky  = |sig_r[W-2-KEPT:0];
    assign inexact = guard || sticky;
    assign inc     = round_up(rm, sign, frac[0], guard, sticky);

    // The exponent field: exp, or 0 below the normal range (exp's bits ANDed with !below).
    assign word = {exp & {EXP_WIDTH{!below}}, frac};

    Incr #(.WIDTH(WORD)) u_incr_word(.in(word), .out(word_inc), .co(word_co));
    Mux2 #(.WIDTH(WORD)) u_mux2_word(.in0(word), .in1(word_inc), .sel(inc), .out(word_r));

    CmpGe #(.WIDTH(EXP_WIDTH)) u_cmp_ge_overflow(
        .in1(word_r[WORD-1:FP32_MANT_WIDTH]), .in2(EXP_WIDTH'(2 ** FP32_EXP_WIDTH - 1)),
        .ge(overflow));

    assign to_inf = rm == RM_RNE || rm == RM_RMM || (rm == RM_RUP && !sign) ||
                    (rm == RM_RDN && sign);

    Mux2 #(.WIDTH(FP)) u_mux2_ovf(
        .in0({{(FP32_EXP_WIDTH - 1){1'b1}}, 1'b0, {FP32_MANT_WIDTH{1'b1}}}),
        .in1({{FP32_EXP_WIDTH{1'b1}}, {FP32_MANT_WIDTH{1'b0}}}), .sel(to_inf),
        .out(ovf_value));
    // 0: the rounded word, 1: overflow, 2 and 3: zero.
    Mux4 #(.WIDTH(FP)) u_mux4_result(
        .in0(word_r[FP-1:0]), .in1(ovf_value), .in2('0), .in3('0), .sel({zero, overflow}),
        .out(magnitude));
    assign result = {sign, magnitude};

    assign carry_n = (&sig[W-1 -: KEPT]) && round_up(rm, sign, 1'b1, sig[W-1-KEPT],
                                                     |sig[W-2-KEPT:0]);
    assign tiny    = exp[EXP_WIDTH-1] || (~|exp && !carry_n);

    assign flags.nv = 1'b0;
    assign flags.dz = 1'b0;
    assign flags.of = !zero && overflow;
    assign flags.uf = !zero && !overflow && tiny && inexact;
    assign flags.nx = !zero && (overflow || inexact);

endmodule

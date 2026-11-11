/* Fp32 to integer: an fp32 to a 32-bit signed or unsigned integer by a rounding mode (RISC-V
 * FCVT.W.S, FCVT.WU.S), the result of an invalid conversion a parameter, hybrid.
 *
 * The significand (24 bits, the hidden bit on top) is placed at the top of a 58-bit field
 * whose bits 57..26 are the integer, bit 25 the guard bit and 24..0 the sticky bits, and
 * shifted right by s = 158 - exp: its top bit then has the weight 2^(exp - 127). The top 1
 * stays in the field for s up to 57, so the bits shifted out never decide sticky (when they
 * are lost, the top 1 is among the sticky bits already); s of 58 or more (exp up to 100) is
 * a value below 2^-27: integer and guard 0, sticky set unless x is 0. FpPkg::round_up says
 * whether to add one by rm. Rounding and negating take one increment: a negative signed
 * result is -(int + r) = ~int + (1 - r), so the integer, inverted for it, goes into one
 * Incr and the carry in (r, or 1 - r) picks the sum or the integer (Mux2); not an Incr for
 * the rounding and another for the negation in series (kb rtl/lib/numeric/fp32/simple_ops).
 * Invalid: a NaN; exp above 158 (2^32 or more, infinities too); the rounded magnitude out
 * of range: signed above 2^31 - 1 (above 2^31 for a negative value), unsigned 2^32 or more,
 * or any negative value that does not round to 0; told from the integer before rounding
 * (all ones, 2^31 - 1 and 2^31 exactly are where one more crosses a limit) and r, beside
 * the increment. Then NV alone, and the integer INVALID
 * (FpPkg::toint_invalid_e) says: TOINT_RISCV the largest integer for a NaN or a value too
 * large, the smallest for one too small (0 unsigned); TOINT_ARM the same but 0 for a NaN.
 * Otherwise NX when the value was not an integer. Hybrid (AGENTS.md): the subtraction,
 * the shift, the increments, the compare and the wide selects are library blocks, parts and
 * gates; the range checks and flags are glue.
 *
 *   x --> Fp32Unpack --> BrentKungAdder 158 - exp = s --> CmpGe (>= 58: all sticky)
 *         sig --> BarrelShifter >> s --> integer | guard | sticky
 *         integer (inverted for a negative signed result) --> Incr --> Mux2 (carry in)
 *         integer, round_up --> range, NaN --> Mux2 (the INVALID integer) --> result; flags
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module Fp32ToInt import Fp32Pkg::*, FpPkg::*; #(
    parameter toint_invalid_e INVALID = TOINT_RISCV    // the integer of an invalid conversion
)(
    input  fp32_t       x,
    input  wire         is_signed,  // 1: to an int32 (FCVT.W.S), 0: to a uint32 (FCVT.WU.S)
    input  rm_e         rm,         // rounding mode
    output logic [31:0] result,
    output flags_t      flags       // NV or NX; the others 0
);
    localparam int P  = FP32_MANT_WIDTH + 1;    // 24: bits of the significand
    localparam int W  = 58;                     // the field: 32 integer bits, guard, 25 sticky
    localparam int SW = $clog2(W);              // 6: bits of a shift below W
    localparam int EW = FP32_EXP_WIDTH + 1;     // 9: s, signed

    // Of x unpacked only the sign, exp, sig and the classes are used.
    /* verilator lint_off UNUSEDSIGNAL */
    fp32_unpacked_t u;
    /* verilator lint_on UNUSEDSIGNAL */
    logic [EW-1:0]  s;          // 158 - exp, signed
    logic           big;        // exp above 158: 2^32 or more
    logic           s_ge_w;     // s >= 58 (s not negative)
    logic           tiny;       // a value below 2^-27
    logic [W-1:0]   shifted;
    logic [W-1:0]   field;      // the shifted significand, 0 when tiny
    logic [31:0]    int_part;
    logic           guard;
    logic           sticky;
    logic           inc;        // round up
    logic           neg;        // a negative signed result
    logic [31:0]    pre;        // int_part, inverted when neg
    logic [31:0]    pre_inc;    // pre + 1
    logic           cin;        // add 1: inc, or !inc when neg
    logic           all_ones;   // int_part is 2^32 - 1
    logic           low_ones;   // int_part's bits 30..0 are ones
    logic           low_zero;   // ... are zeros
    logic           in_range;
    logic [31:0]    value;      // the valid result
    logic           invalid;
    logic [31:0]    inv_value;  // the integer of an invalid conversion
    // Carries out: not used.
    /* verilator lint_off UNUSEDSIGNAL */
    logic           s_co;
    logic           pre_co;
    /* verilator lint_on UNUSEDSIGNAL */

    Fp32Unpack u_unpack(.x, .u);

    // s = 158 - exp = 158 + ~exp + 1.
    BrentKungAdder #(.WIDTH(EW)) u_adder_s(
        .in1(EW'(158)), .in2(~EW'(u.exp)), .ci(1'b1), .co(s_co), .sum(s));
    CmpGe #(.WIDTH(EW)) u_cmp_ge_s(.in1(s), .in2(EW'(W)), .ge(s_ge_w));
    assign big   = s[EW-1];
    assign tiny  = s_ge_w && !big;

    BarrelShifter #(.WIDTH(W)) u_shifter(
        .in({u.sig, {(W - P){1'b0}}}), .shift_in_bit(1'b0), .shift(s[SW-1:0]),
        .shift_rotate(1'b1), .left_right(1'b0), .out(shifted));
    assign field = shifted & {W{!tiny}};

    assign int_part = field[W-1 -: 32];
    assign guard    = field[W-33];
    assign sticky   = |field[W-34:0] || (tiny && !u.zero);
    assign inc      = round_up(rm, u.sign, int_part[0], guard, sticky);

    // Rounded and negated in one increment: -(int + inc) = ~int + !inc.
    // @kb: rtl/lib/numeric/fp32/simple_ops
    assign neg = is_signed && u.sign;
    assign pre = int_part ^ {32{neg}};
    assign cin = inc ^ neg;
    Incr #(.WIDTH(32)) u_incr(.in(pre), .out(pre_inc), .co(pre_co));
    Mux2 #(.WIDTH(32)) u_mux2_round(.in0(pre), .in1(pre_inc), .sel(cin), .out(value));

    // In range, from the integer before rounding: signed up to 2^31 - 1 (2^31 for a negative
    // value), unsigned below 2^32 (0 for a negative value).
    assign low_ones = &int_part[30:0];
    assign low_zero = ~|int_part[30:0];
    assign all_ones = int_part[31] && low_ones;
    always_comb
        if (is_signed)
            in_range = u.sign ? !int_part[31] || (low_zero && !inc)
                              : !int_part[31] && !(low_ones && inc);
        else
            in_range = u.sign ? !int_part[31] && low_zero && !inc
                              : !(all_ones && inc);
    assign invalid  = u.nan || big || !in_range;

    // The integer of an invalid conversion: the largest, the smallest, or for a NaN by INVALID.
    if (INVALID == TOINT_ARM) begin: g_arm
        assign inv_value = u.nan ? '0 : !u.sign ? {!is_signed, 31'h7fff_ffff}
                                                : {is_signed, 31'h0};
    end else begin: g_riscv
        assign inv_value = (u.nan || !u.sign) ? {!is_signed, 31'h7fff_ffff}
                                              : {is_signed, 31'h0};
    end

    Mux2 #(.WIDTH(32)) u_mux2_result(
        .in0(value), .in1(inv_value), .sel(invalid), .out(result));

    assign flags.nv = invalid;
    assign flags.dz = 1'b0;
    assign flags.of = 1'b0;
    assign flags.uf = 1'b0;
    assign flags.nx = !invalid && (guard || sticky);

endmodule

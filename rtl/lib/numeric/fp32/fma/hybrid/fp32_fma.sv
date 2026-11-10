/* Fp32 fused multiply-add: a * b + c with one rounding, and its special cases add,
 * subtract and multiply (RISC-V FMADD.S, FMSUB.S, FNMSUB.S, FNMADD.S, FADD.S, FSUB.S,
 * FMUL.S), hybrid.
 *
 * op (FpPkg::fma_op_e) says what a, b and c are, as a core's rs1, rs2 and rs3: MADD
 * a*b + c, MSUB a*b - c, NMSUB -(a*b) + c, NMADD -(a*b) - c; ADD a + b and SUB a - b are
 * a * 1.0 + b and a * 1.0 - b (the multiplier gets 1.0, the addend b); MUL is a * b with
 * no addend (a zero with the product's sign, so that a zero product keeps its sign in every
 * rounding mode). The exact value goes to Fp32Round, so every result is rounded once.
 *  - Unpack (Fp32Unpack): signs, exponents (1 for a subnormal), significands of 24 bits,
 *    classes. A subnormal significand is not normalized: the sum is normalized later.
 *  - The field: 76 bits. Bit 75 is the sign of a difference, bit 0 a sticky bit (the jam);
 *    the product, 48 bits, sits at bits 48..1, the addend first at bits 74..51 (its top bit
 *    26 above the product's) and shifted right by sh = 27 + e_p - e_c, e_p = e_a + e_b - 127
 *    the product's exponent. sh <= 0 (or a zero product) leaves it on top (clamp): the
 *    product is then at least 2 bits below it, which rounds the same as its true place, and
 *    the field counts from the addend's exponent instead of the product's; the bits shifted
 *    out below bit 0 are ORed into bit 0 (sh of 128 or more: all of them).
 *  - The 24 partial products of the significands and the aligned addend (inverted when the
 *    product and the addend have opposite signs: an effective subtraction) are the 25 rows
 *    of a WallaceTree: the addend joins the product's tree, and one KoggeStoneAdder (carry
 *    in 1 for a subtraction) adds the two rows left. A negative difference is negated
 *    (Incr of the inverse) and takes the addend's sign.
 *  - The top 1 of the magnitude (PriorityEncoder, 128 inputs) gives the exponent,
 *    e_base - 47 + its index (e_base: e_p, or e_c - 27 with the clamp, where the addend's
 *    top bit 74 has exponent e_c), and the left shift (BarrelShifter) that puts it on top; the top
 *    25 bits and the OR of the rest go to Fp32Round (26 bits) with that exponent, which
 *    makes subnormals, rounds and flags overflow, underflow and inexact.
 *  - An exact zero: the sign of both operands when they agree (two zeros of one sign), else
 *    +0, or -0 rounding down (RDN).
 *  - Special cases: a NaN operand, infinity times zero, or infinities of opposite signs
 *    added give the default NaN (0x7fc00000, no payload); NV for a signalling NaN, for
 *    infinity times zero (also with a quiet NaN addend: RISC-V's rule) and for the
 *    infinities. Otherwise an infinite product or addend gives that infinity, no flags.
 * Combinational; where a core puts registers is its choice. Hybrid (AGENTS.md): the
 * multiplier tree, the adders, the shifts, the leading-one search, the negation and the
 * wide selects are library blocks, parts and gates; the narrow glue is operators.
 *
 *   a, b, c, op --> Mux2 (ADD/SUB: b <- 1.0, c <- b) --> Fp32Unpack x 3
 *   e_a + e_b - 127 = e_p (BrentKungAdder x 2); sh = e_p - e_c + 27 (CarrySaveAdder + BK)
 *   addend --> BarrelShifter >> sh (+ mask, jam) --> row 24 (inverted for a difference)
 *   sig_a & sig_b[j] << j + 1 --> rows 0..23 --> WallaceTree --> KoggeStoneAdder --> sum
 *   sum < 0: Incr(~sum) --> magnitude --> PriorityEncoder --> index t --> e_base - 47 + t
 *                                     --> BarrelShifter << 74 - t --> 25 bits + sticky
 *   --> Fp32Round --> Mux4 (rounded, infinity, default NaN) --> result, flags
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module Fp32Fma import Fp32Pkg::*, FpPkg::*; (
    input  fp32_t   a,          // rs1
    input  fp32_t   b,          // rs2
    input  fp32_t   c,          // rs3 (MADD, MSUB, NMSUB, NMADD)
    input  fma_op_e op,
    input  rm_e     rm,         // rounding mode
    output fp32_t   result,
    output flags_t  flags       // NV, OF, UF, NX; DZ 0
);
    localparam int P   = FP32_MANT_WIDTH + 1;   // 24: bits of a significand
    localparam int F   = 3 * P + 4;             // 76: the field
    localparam int FA  = F - 1;                 // 75: the field below its sign bit
    localparam int EW  = 10;                    // exponents, signed
    localparam int SHW = 7;                     // shifts of the field: 0..127
    localparam int RS  = P + 2;                 // 26: bits to Fp32Round

    // Operands by op.
    logic           is_add;     // ADD, SUB: a * 1.0 + b
    logic           mul_only;   // MUL: no addend
    fp32_t          b_m;        // the multiplier's second operand
    fp32_t          c_m;        // the addend
    // Their subnormal flags: not used (a subnormal significand goes in as it is).
    /* verilator lint_off UNUSEDSIGNAL */
    fp32_unpacked_t ua;
    fp32_unpacked_t ub;
    fp32_unpacked_t uc;
    /* verilator lint_on UNUSEDSIGNAL */
    logic           neg_prod;   // the product is negated
    logic           neg_add;    // the addend is negated
    logic           sign_p;     // the product's sign
    logic           sign_c;     // the addend's sign
    logic           p_zero;     // the product is 0
    logic           c_zero;     // the addend is 0, or there is none
    logic           c_inf;
    logic           c_nan;
    logic           c_snan;
    logic [P-1:0]   sig_c;      // the addend's significand, 0 when there is none
    logic           sub;        // the product and the addend have opposite signs

    assign is_add   = op == FMA_ADD || op == FMA_SUB;
    assign mul_only = op == FMA_MUL;

    Mux2 #(.WIDTH($bits(fp32_t))) u_mux2_b(.in0(b), .in1(FP32_ONE), .sel(is_add), .out(b_m));
    Mux2 #(.WIDTH($bits(fp32_t))) u_mux2_c(.in0(c), .in1(b), .sel(is_add), .out(c_m));

    Fp32Unpack u_unpack_a(.x(a), .u(ua));
    Fp32Unpack u_unpack_b(.x(b_m), .u(ub));
    Fp32Unpack u_unpack_c(.x(c_m), .u(uc));

    assign neg_prod = op == FMA_NMSUB || op == FMA_NMADD;
    assign neg_add  = op == FMA_MSUB || op == FMA_NMADD || op == FMA_SUB;
    assign sign_p   = ua.sign ^ ub.sign ^ neg_prod;
    assign sign_c   = mul_only ? sign_p : uc.sign ^ neg_add;
    assign p_zero   = ua.zero || ub.zero;
    assign c_zero   = uc.zero || mul_only;
    assign c_inf    = uc.inf && !mul_only;
    assign c_nan    = uc.nan && !mul_only;
    assign c_snan   = uc.snan && !mul_only;
    assign sig_c    = uc.sig & {P{!mul_only}};
    assign sub      = sign_p ^ sign_c;

    // Exponents: e_p = e_a + e_b - 127, sh = e_p - e_c + 27 = e_p + ~e_c + 28.
    logic [EW-1:0]  e_ab;       // e_a + e_b
    logic [EW-1:0]  e_p;        // the product's exponent (of its bit 46), signed
    logic [EW-1:0]  sh_ps;      // sh as partial sum and shifted carries
    logic [EW-1:0]  sh;         // signed
    logic           clamp;      // sh <= 0 or a zero product: the addend stays on top
    logic [SHW-1:0] sh_eff;     // 0 with the clamp, 127 for 128 or more
    logic [EW-1:0]  e_c27;      // e_c - 27
    logic [EW-1:0]  e_base;     // the exponent the field counts from (of its bit 47)
    // Carries out, and the top bit of the shifted carries: not used (the sums are taken mod
    // 2^EW, signed).
    /* verilator lint_off UNUSEDSIGNAL */
    logic [EW-1:0]  sh_sc;
    logic           e_ab_co;
    logic           e_p_co;
    logic           sh_co;
    logic           e_c27_co;
    /* verilator lint_on UNUSEDSIGNAL */

    BrentKungAdder #(.WIDTH(EW)) u_adder_e_ab(
        .in1(EW'(ua.exp)), .in2(EW'(ub.exp)), .ci(1'b0), .co(e_ab_co), .sum(e_ab));
    BrentKungAdder #(.WIDTH(EW)) u_adder_e_p(
        .in1(e_ab), .in2(-EW'(FP32_BIAS)), .ci(1'b0), .co(e_p_co), .sum(e_p));
    CarrySaveAdder #(.WIDTH(EW)) u_csa_sh(
        .in1(e_p), .in2(~EW'(uc.exp)), .in3(EW'(28)), .ps(sh_ps), .sc(sh_sc));
    BrentKungAdder #(.WIDTH(EW)) u_adder_sh(
        .in1(sh_ps), .in2({sh_sc[EW-2:0], 1'b0}), .ci(1'b0), .co(sh_co), .sum(sh));

    // A zero addend (or none, MUL) adds nothing: the field counts from the product.
    assign clamp  = p_zero || (sh[EW-1] && !c_zero);
    assign sh_eff = clamp ? '0 : (|sh[EW-2:SHW]) ? '1 : sh[SHW-1:0];

    // The field's exponent: the product's, or with the clamp the addend's less 27.
    BrentKungAdder #(.WIDTH(EW)) u_adder_e_c27(
        .in1(EW'(uc.exp)), .in2(-EW'(27)), .ci(1'b0), .co(e_c27_co), .sum(e_c27));
    Mux2 #(.WIDTH(EW)) u_mux2_e_base(.in0(e_p), .in1(e_c27), .sel(clamp), .out(e_base));

    // The addend in the field, aligned; the bits shifted out jammed into bit 0.
    logic [FA-1:0]  c_top;      // the addend on top: bits 74..51
    logic [FA-1:0]  c_shifted;
    logic [FA-1:0]  c_keep;     // ones << sh: the bits that stay in the field
    logic           c_lost;     // a 1 shifted out
    logic [FA-1:0]  c_al;       // the addend aligned, with the jam

    assign c_top = {sig_c, {(FA - P){1'b0}}};
    BarrelShifter #(.WIDTH(FA)) u_shifter_c(
        .in(c_top), .shift_in_bit(1'b0), .shift(sh_eff), .shift_rotate(1'b1),
        .left_right(1'b0), .out(c_shifted));
    BarrelShifter #(.WIDTH(FA)) u_shifter_c_mask(
        .in({FA{1'b1}}), .shift_in_bit(1'b0), .shift(sh_eff), .shift_rotate(1'b1),
        .left_right(1'b1), .out(c_keep));
    assign c_lost = |(c_top & ~c_keep);
    assign c_al   = {c_shifted[FA-1:1], c_shifted[0] || c_lost};

    // The product's partial products and the addend: one tree, one adder.
    logic [F-1:0]   rows [P+1];
    logic [F-1:0]   tree_sum;
    logic [F-1:0]   tree_carry;
    logic [F-1:0]   s;          // product + addend, or product - addend (two's complement)
    logic [F-1:0]   s_neg;      // -s
    logic [F-1:0]   mag;        // |s|
    logic           neg;        // s < 0: the addend is the larger
    // Carries out: not used (the sum is taken mod 2^F, its sign is bit F-1).
    /* verilator lint_off UNUSEDSIGNAL */
    logic           s_co;
    logic           s_neg_co;
    /* verilator lint_on UNUSEDSIGNAL */

    for (genvar j = 0; j < P; j++) begin: g_pp
        logic [P-1:0] pp;           // sig_a & sig_b[j]
        assign pp      = ua.sig & {P{ub.sig[j]}};
        assign rows[j] = F'(pp) << (j + 1);
    end
    assign rows[P] = {1'b0, c_al} ^ {F{sub}};

    WallaceTree #(.ROWS(P + 1), .WIDTH(F)) u_wallace_tree(
        .rows, .sum(tree_sum), .carry(tree_carry));
    KoggeStoneAdder #(.WIDTH(F)) u_adder_s(
        .in1(tree_sum), .in2(tree_carry), .ci(sub), .co(s_co), .sum(s));

    assign neg = s[F-1];
    Incr #(.WIDTH(F)) u_incr_neg(.in(~s), .out(s_neg), .co(s_neg_co));
    Mux2 #(.WIDTH(F)) u_mux2_mag(.in0(s), .in1(s_neg), .sel(neg), .out(mag));

    // Normalize: the top 1 of the magnitude to bit 74.
    logic [SHW-1:0] t;          // index of the top 1
    logic           nonzero;    // the sum is not exactly 0
    logic [SHW-1:0] shn;        // 74 - t = ~t + 75, mod 128
    logic [FA-1:0]  norm;
    logic [EW-1:0]  e_r_ps;     // e_base - 47 + t as partial sum and shifted carries
    logic [EW-1:0]  e_r;        // the exponent of the top 1, signed
    logic [RS-1:0]  sig_r;      // the top 25 bits and the sticky OR of the rest
    // Carries out, the top bit of the shifted carries and the magnitude's sign bit (0): not
    // used.
    /* verilator lint_off UNUSEDSIGNAL */
    logic [EW-1:0]  e_r_sc;
    logic           shn_co;
    logic           e_r_co;
    logic           mag_top;
    /* verilator lint_on UNUSEDSIGNAL */

    assign mag_top = mag[F-1];
    PriorityEncoder #(.SIZE(SHW)) u_priority_encoder(
        .in({{(2 ** SHW - FA){1'b0}}, mag[FA-1:0]}), .out(t), .valid(nonzero));
    BrentKungAdder #(.WIDTH(SHW)) u_adder_shn(
        .in1(~t), .in2(SHW'(FA)), .ci(1'b0), .co(shn_co), .sum(shn));
    BarrelShifter #(.WIDTH(FA)) u_shifter_norm(
        .in(mag[FA-1:0]), .shift_in_bit(1'b0), .shift(shn), .shift_rotate(1'b1),
        .left_right(1'b1), .out(norm));
    assign sig_r = {norm[FA-1 -: RS-1], |norm[FA-RS:0]};

    CarrySaveAdder #(.WIDTH(EW)) u_csa_e_r(
        .in1(e_base), .in2(EW'(t)), .in3(-EW'(47)), .ps(e_r_ps), .sc(e_r_sc));
    BrentKungAdder #(.WIDTH(EW)) u_adder_e_r(
        .in1(e_r_ps), .in2({e_r_sc[EW-2:0], 1'b0}), .ci(1'b0), .co(e_r_co), .sum(e_r));

    // Round; an exact zero gets its sign here.
    logic           sign_r;     // the sign of a nonzero sum
    logic           zero_sign;  // the sign of an exact zero
    fp32_t          rounded;
    // Its NV and DZ (0): not used.
    /* verilator lint_off UNUSEDSIGNAL */
    flags_t         round_flags;
    /* verilator lint_on UNUSEDSIGNAL */

    assign sign_r    = neg ? sign_c : sign_p;
    assign zero_sign = (sign_p == sign_c) ? sign_p : rm == RM_RDN;

    Fp32Round #(.SIG_WIDTH(RS), .EXP_WIDTH(EW)) u_round(
        .sign(nonzero ? sign_r : zero_sign), .exp(e_r), .sig(sig_r), .rm,
        .result(rounded), .flags(round_flags));

    // Special cases.
    logic           p_inf;          // the product is infinite (no NaN operand)
    logic           inf_times_zero;
    logic           inf_cancel;     // infinities of opposite signs added
    logic           nan_res;        // the result is the default NaN
    logic           inf_res;        // the result is an infinity
    logic           invalid;
    fp32_t          inf_value;

    assign p_inf          = (ua.inf || ub.inf) && !ua.nan && !ub.nan;
    assign inf_times_zero = (ua.inf && ub.zero) || (ua.zero && ub.inf);
    assign inf_cancel     = p_inf && c_inf && sub;
    assign nan_res        = ua.nan || ub.nan || c_nan || inf_times_zero || inf_cancel;
    assign inf_res        = p_inf || c_inf;
    assign invalid        = ua.snan || ub.snan || c_snan || inf_times_zero || inf_cancel;
    assign inf_value      = {p_inf ? sign_p : sign_c, {FP32_EXP_WIDTH{1'b1}},
                             {FP32_MANT_WIDTH{1'b0}}};

    // 0: rounded, 1: an infinity, 2 and 3: the default NaN.
    Mux4 #(.WIDTH($bits(fp32_t))) u_mux4_result(
        .in0(rounded), .in1(inf_value), .in2(FP32_DEFAULT_NAN), .in3(FP32_DEFAULT_NAN),
        .sel({nan_res, inf_res}), .out(result));
    // A special result is exact: NV only; else the rounding's flags (its NV and DZ are 0).
    assign flags.nv = (nan_res || inf_res) && invalid;
    assign flags.dz = 1'b0;
    assign flags.of = !nan_res && !inf_res && round_flags.of;
    assign flags.uf = !nan_res && !inf_res && round_flags.uf;
    assign flags.nx = !nan_res && !inf_res && round_flags.nx;

endmodule

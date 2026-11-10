/* Fp32 fused multiply-add: a * b + c with one rounding, and its special cases add,
 * subtract and multiply (RISC-V FMADD.S, FMSUB.S, FNMSUB.S, FNMADD.S, FADD.S, FSUB.S,
 * FMUL.S), with 0 to 3 pipeline stages, hybrid.
 *
 * op (FpPkg::fma_op_e) says what a, b and c are, as a core's rs1, rs2 and rs3: MADD
 * a*b + c, MSUB a*b - c, NMSUB -(a*b) + c, NMADD -(a*b) - c; ADD a + b and SUB a - b are
 * a * 1.0 + b and a * 1.0 - b (the multiplier gets 1.0, the addend b); MUL is a * b with
 * no addend (a zero with the product's sign, so that a zero product keeps its sign in every
 * rounding mode). The exact value goes to Fp32Round, so every result is rounded once.
 *  - Unpack (Fp32Unpack): signs, exponents (1 for a subnormal), significands of 24 bits,
 *    classes. A subnormal significand is not normalized: the sum is normalized later.
 *  - The field: 77 bits. Bit 76 is the sign of a difference, bit 0 a sticky bit (the jam),
 *    bit 1 always 0 (so that the jam stays below the guard bit when the product is only 24
 *    bits long: a normal times a subnormal); the product, 48 bits, sits at bits 49..2, the
 *    addend first at bits 75..52 (its top bit 26 above the product's) and shifted right by
 *    sh = 27 + e_p - e_c, e_p = e_a + e_b - 127 the product's exponent. sh <= 0 (or a zero
 *    product) leaves it on top (clamp): the product is then at least 2 bits below it, which
 *    rounds the same as its true place, and the field counts from the addend's exponent
 *    instead of the product's; the bits shifted out below bit 0 are ORed into bit 0 (sh of
 *    128 or more: all of them).
 *  - The 24 partial products of the significands are the rows of a WallaceTree, while the
 *    addend is aligned beside it; one CarrySaveAdder adds the aligned addend (inverted when
 *    the product and the addend have opposite signs: an effective subtraction) to the
 *    tree's two rows (the addend off the tree's path: STAGES 3 timing), and one
 *    KoggeStoneAdder (carry in 1 for a subtraction) adds the two rows left. A negative
 *    difference is negated (Incr of the inverse) and takes the addend's sign.
 *  - The top 1 of the magnitude (PriorityEncoder, 128 inputs) gives the exponent,
 *    e_base - 48 + its index (e_base: e_p, or e_c - 27 with the clamp, where the addend's
 *    top bit 75 has exponent e_c), and the left shift (BarrelShifter) that puts it on top;
 *    the top 25 bits and the OR of the rest go to Fp32Round (26 bits) with that exponent,
 *    which makes subnormals, rounds and flags overflow, underflow and inexact.
 *  - An exact zero: the sign of both operands when they agree (two zeros of one sign), else
 *    +0, or -0 rounding down (RDN).
 *  - Special cases: a NaN operand, infinity times zero, or infinities of opposite signs
 *    added give the default NaN (0x7fc00000, no payload); NV for a signalling NaN, for
 *    infinity times zero (also with a quiet NaN addend: RISC-V's rule) and for the
 *    infinities. Otherwise an infinite product or addend gives that infinity, no flags.
 * Pipeline: STAGES registers at fixed stage boundaries, each a DelayLine (DEPTH 1, or 0: a
 * wire) carrying a packed struct of everything that crosses it; the logic after a boundary
 * reads only that struct. STAGES 0: combinational (clk, rst_n, in_valid unused for data);
 * otherwise result, flags and out_valid come STAGES rising edges after a, b, c, op, rm and
 * in_valid, and a new operation may enter every clock (no stall: a core that holds an
 * operation holds its inputs). The boundaries by STAGES (kb rtl/lib/numeric/fp32/fma_stages):
 *     STAGES   after the tree   after the adder   after normalizing
 *       0           -                 -                  -
 *       1           -                 x                  -
 *       2           x                 -                  x
 *       3           x                 x                  x
 * Hybrid (AGENTS.md): the multiplier tree, the adders, the shifts, the leading-one search,
 * the negation, the wide selects and the stage registers are library blocks, parts and
 * gates; the narrow glue is operators.
 *
 *   a, b, c, op --> Mux2 (ADD/SUB: b <- 1.0, c <- b) --> Fp32Unpack x 3
 *   e_a + e_b - 127 = e_p (BrentKungAdder x 2); sh = e_p - e_c + 27 (CarrySaveAdder + BK)
 *   sig_a & sig_b[j] << j + 2 --> rows 0..23 --> WallaceTree --> product: sum, carry
 *   addend --> BarrelShifter >> sh (+ mask, jam) --> inverted for a difference
 *   product sum, carry, addend --> CarrySaveAdder --> sum, carry
 *   ======== stage boundary: tree (sum, carry, signs, e_base, rm, special case) ========
 *   KoggeStoneAdder --> s; s < 0: Incr(~s) --> magnitude, its sign
 *   ======== stage boundary: adder (magnitude, sign, e_base, rm, special case) ========
 *   PriorityEncoder --> index t --> e_base - 48 + t; BarrelShifter << 75 - t --> 25 + sticky
 *   ======== stage boundary: norm (significand, exponent, sign, rm, special case) ========
 *   Fp32Round --> Mux4 (rounded, infinity, default NaN) --> result, flags
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
`include "dark_circuit_assert.svh"

module Fp32Fma import Fp32Pkg::*, FpPkg::*; #(
    parameter int STAGES = 0            // pipeline stages: 0 (combinational) to 3
)(
    input  wire     clk,
    input  wire     rst_n,              // synchronous reset, active low: out_valid 0
    input  wire     in_valid,           // a, b, c, op, rm are an operation
    input  fp32_t   a,                  // rs1
    input  fp32_t   b,                  // rs2
    input  fp32_t   c,                  // rs3 (MADD, MSUB, NMSUB, NMADD)
    input  fma_op_e op,
    input  rm_e     rm,                 // rounding mode
    output wire     out_valid,          // result and flags are the operation's, STAGES later
    output fp32_t   result,
    output flags_t  flags               // NV, OF, UF, NX; DZ 0
);
    localparam int P   = FP32_MANT_WIDTH + 1;   // 24: bits of a significand
    localparam int F   = 3 * P + 5;             // 77: the field
    localparam int FA  = F - 1;                 // 76: the field below its sign bit
    localparam int EW  = 10;                    // exponents, signed
    localparam int SHW = 7;                     // shifts of the field: 0..127
    localparam int RS  = P + 2;                 // 26: bits to Fp32Round

    // @kb: rtl/lib/numeric/fp32/fma_stages
    // The stage boundaries that are registers (the table in the header).
    localparam int BOUNDARY_TREE  = (STAGES >= 2) ? 1 : 0;
    localparam int BOUNDARY_ADDER = (STAGES == 1 || STAGES == 3) ? 1 : 0;
    localparam int BOUNDARY_NORM  = (STAGES >= 2) ? 1 : 0;

    `DC_STATIC_ASSERT(a_stages, STAGES >= 0 && STAGES <= 3)

    // A special result, decided from the operands: it travels with the operation.
    typedef struct packed {
        logic nan;          // the default NaN
        logic inf;          // an infinity
        logic inf_sign;     // its sign
        logic nv;           // invalid (with the NaN)
    } special_t;

    // What crosses each stage boundary.
    typedef struct packed {
        logic [F-1:0]  tree_sum;    // the tree's two rows: product + addend
        logic [F-1:0]  tree_carry;
        logic          sub;         // an effective subtraction: carry in 1
        logic          sign_p;      // the product's sign
        logic          sign_c;      // the addend's sign
        logic          zero_sign;   // the sign of an exact zero
        logic [EW-1:0] e_base;      // the exponent the field counts from
        rm_e           rm;
        special_t      special;
    } stage_boundary_tree_t;

    typedef struct packed {
        logic [FA-1:0] mag;         // |sum| (its sign bit, 0, dropped)
        logic          sign;        // the sign of a nonzero sum
        logic          zero_sign;
        logic [EW-1:0] e_base;
        rm_e           rm;
        special_t      special;
    } stage_boundary_adder_t;

    typedef struct packed {
        logic [RS-1:0] sig;         // the top 25 bits and the sticky OR of the rest
        logic [EW-1:0] exp;         // the exponent of the top 1, signed
        logic          sign;        // the result's sign (an exact zero's too)
        rm_e           rm;
        special_t      special;
    } stage_boundary_norm_t;

    stage_boundary_tree_t  tree_in;     // before the boundary
    stage_boundary_tree_t  tree;        // after it: the only one the adder reads
    stage_boundary_adder_t adder_in;
    stage_boundary_adder_t adder;
    stage_boundary_norm_t  norm_in;
    stage_boundary_norm_t  norm;

    // ---------------- Unpack, exponents, alignment, the tree ----------------

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
    Mux2 #(.WIDTH(EW)) u_mux2_e_base(
        .in0(e_p), .in1(e_c27), .sel(clamp), .out(tree_in.e_base));

    // The addend in the field, aligned; the bits shifted out jammed into bit 0.
    logic [FA-1:0]  c_top;      // the addend on top: bits 75..52
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

    // The product's partial products in the tree, while the addend is aligned; then one
    // carry-save adder takes the tree's two rows and the addend (inverted for a
    // difference) to two rows.
    logic [F-1:0]   rows [P];
    logic [F-1:0]   prod_sum;   // the tree's rows: the product
    logic [F-1:0]   prod_carry;
    logic [F-1:0]   add_row;    // the addend, inverted for a difference
    logic [F-1:0]   csa_sc;     // the carry-save adder's carries, of weight 2
    // The top bit of its carries: shifted out (sums mod 2^F).
    /* verilator lint_off UNUSEDSIGNAL */
    logic           csa_sc_top;
    /* verilator lint_on UNUSEDSIGNAL */

    for (genvar j = 0; j < P; j++) begin: g_pp
        logic [P-1:0] pp;           // sig_a & sig_b[j]
        assign pp      = ua.sig & {P{ub.sig[j]}};
        assign rows[j] = F'(pp) << (j + 2);
    end

    WallaceTree #(.ROWS(P), .WIDTH(F)) u_wallace_tree(
        .rows, .sum(prod_sum), .carry(prod_carry));

    assign add_row = {1'b0, c_al} ^ {F{sub}};
    CarrySaveAdder #(.WIDTH(F)) u_csa_addend(
        .in1(prod_sum), .in2(prod_carry), .in3(add_row), .ps(tree_in.tree_sum), .sc(csa_sc));
    assign csa_sc_top         = csa_sc[F-1];
    assign tree_in.tree_carry = {csa_sc[F-2:0], 1'b0};

    // Special cases, from the operands.
    logic           p_inf;          // the product is infinite (no NaN operand)
    logic           inf_times_zero;
    logic           inf_cancel;     // infinities of opposite signs added

    assign p_inf          = (ua.inf || ub.inf) && !ua.nan && !ub.nan;
    assign inf_times_zero = (ua.inf && ub.zero) || (ua.zero && ub.inf);
    assign inf_cancel     = p_inf && c_inf && sub;

    assign tree_in.special.nan      = ua.nan || ub.nan || c_nan || inf_times_zero || inf_cancel;
    assign tree_in.special.inf      = p_inf || c_inf;
    assign tree_in.special.inf_sign = p_inf ? sign_p : sign_c;
    assign tree_in.special.nv       = ua.snan || ub.snan || c_snan || inf_times_zero ||
                                      inf_cancel;

    assign tree_in.sub       = sub;
    assign tree_in.sign_p    = sign_p;
    assign tree_in.sign_c    = sign_c;
    assign tree_in.zero_sign = (sign_p == sign_c) ? sign_p : rm == RM_RDN;
    assign tree_in.rm        = rm;

    DelayLine #(.WIDTH($bits(stage_boundary_tree_t)), .DEPTH(BOUNDARY_TREE))
        u_stage_boundary_tree(.clk, .rst_n, .in(tree_in), .out(tree));

    // ---------------- The adder, the negation ----------------

    logic [F-1:0]   s;          // product + addend, or product - addend (two's complement)
    logic [F-1:0]   s_neg;      // -s
    logic [F-1:0]   mag;        // |s|
    logic           neg;        // s < 0: the addend is the larger
    // Carries out and the magnitude's sign bit (0): not used.
    /* verilator lint_off UNUSEDSIGNAL */
    logic           s_co;
    logic           s_neg_co;
    logic           mag_top;
    /* verilator lint_on UNUSEDSIGNAL */

    KoggeStoneAdder #(.WIDTH(F)) u_adder_s(
        .in1(tree.tree_sum), .in2(tree.tree_carry), .ci(tree.sub), .co(s_co), .sum(s));

    assign neg = s[F-1];
    Incr #(.WIDTH(F)) u_incr_neg(.in(~s), .out(s_neg), .co(s_neg_co));
    Mux2 #(.WIDTH(F)) u_mux2_mag(.in0(s), .in1(s_neg), .sel(neg), .out(mag));

    assign mag_top            = mag[F-1];
    assign adder_in.mag       = mag[FA-1:0];
    assign adder_in.sign      = neg ? tree.sign_c : tree.sign_p;
    assign adder_in.zero_sign = tree.zero_sign;
    assign adder_in.e_base    = tree.e_base;
    assign adder_in.rm        = tree.rm;
    assign adder_in.special   = tree.special;

    DelayLine #(.WIDTH($bits(stage_boundary_adder_t)), .DEPTH(BOUNDARY_ADDER))
        u_stage_boundary_adder(.clk, .rst_n, .in(adder_in), .out(adder));

    // ---------------- Normalize ----------------

    logic [SHW-1:0] t;          // index of the top 1
    logic           nonzero;    // the sum is not exactly 0
    logic [SHW-1:0] shn;        // 75 - t = ~t + 76, mod 128
    logic [FA-1:0]  normalized;
    logic [EW-1:0]  e_r_ps;     // e_base - 48 + t as partial sum and shifted carries
    // Carries out and the top bit of the shifted carries: not used.
    /* verilator lint_off UNUSEDSIGNAL */
    logic [EW-1:0]  e_r_sc;
    logic           shn_co;
    logic           e_r_co;
    /* verilator lint_on UNUSEDSIGNAL */

    PriorityEncoder #(.SIZE(SHW)) u_priority_encoder(
        .in({{(2 ** SHW - FA){1'b0}}, adder.mag}), .out(t), .valid(nonzero));
    BrentKungAdder #(.WIDTH(SHW)) u_adder_shn(
        .in1(~t), .in2(SHW'(FA)), .ci(1'b0), .co(shn_co), .sum(shn));
    BarrelShifter #(.WIDTH(FA)) u_shifter_norm(
        .in(adder.mag), .shift_in_bit(1'b0), .shift(shn), .shift_rotate(1'b1),
        .left_right(1'b1), .out(normalized));

    CarrySaveAdder #(.WIDTH(EW)) u_csa_e_r(
        .in1(adder.e_base), .in2(EW'(t)), .in3(-EW'(48)), .ps(e_r_ps), .sc(e_r_sc));
    BrentKungAdder #(.WIDTH(EW)) u_adder_e_r(
        .in1(e_r_ps), .in2({e_r_sc[EW-2:0], 1'b0}), .ci(1'b0), .co(e_r_co),
        .sum(norm_in.exp));

    assign norm_in.sig     = {normalized[FA-1 -: RS-1], |normalized[FA-RS:0]};
    assign norm_in.sign    = nonzero ? adder.sign : adder.zero_sign;
    assign norm_in.rm      = adder.rm;
    assign norm_in.special = adder.special;

    DelayLine #(.WIDTH($bits(stage_boundary_norm_t)), .DEPTH(BOUNDARY_NORM))
        u_stage_boundary_norm(.clk, .rst_n, .in(norm_in), .out(norm));

    // ---------------- Round, the special cases ----------------

    fp32_t          rounded;
    // Its NV and DZ (0): not used.
    /* verilator lint_off UNUSEDSIGNAL */
    flags_t         round_flags;
    /* verilator lint_on UNUSEDSIGNAL */
    fp32_t          inf_value;

    Fp32Round #(.SIG_WIDTH(RS), .EXP_WIDTH(EW)) u_round(
        .sign(norm.sign), .exp(norm.exp), .sig(norm.sig), .rm(norm.rm),
        .result(rounded), .flags(round_flags));

    assign inf_value = {norm.special.inf_sign, {FP32_EXP_WIDTH{1'b1}}, {FP32_MANT_WIDTH{1'b0}}};

    // 0: rounded, 1: an infinity, 2 and 3: the default NaN.
    Mux4 #(.WIDTH($bits(fp32_t))) u_mux4_result(
        .in0(rounded), .in1(inf_value), .in2(FP32_DEFAULT_NAN), .in3(FP32_DEFAULT_NAN),
        .sel({norm.special.nan, norm.special.inf}), .out(result));
    // A special result is exact: NV only; else the rounding's flags (its NV and DZ are 0).
    assign flags.nv = (norm.special.nan || norm.special.inf) && norm.special.nv;
    assign flags.dz = 1'b0;
    assign flags.of = !norm.special.nan && !norm.special.inf && round_flags.of;
    assign flags.uf = !norm.special.nan && !norm.special.inf && round_flags.uf;
    assign flags.nx = !norm.special.nan && !norm.special.inf && round_flags.nx;

    // The operation's valid bit, STAGES clocks later; 0 after reset.
    DelayLine #(.WIDTH(1), .DEPTH(STAGES), .RESET(1)) u_valid(
        .clk, .rst_n, .in(in_valid), .out(out_valid));

endmodule

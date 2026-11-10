/* Fp32 divide and square root: a / b or sqrt(a), one result bit per clock (radix-2 digit
 * recurrence, 25 clocks), rounded once (RISC-V FDIV.S, FSQRT.S), hybrid.
 *
 * The handshake of the library's Divider: start=1 while busy=0 takes the operands, sqrt and
 * rm on the rising edge; busy=1 for 25 clocks, done=1 in the last; after that clock, with
 * busy=0 again, result and flags are valid and stay until the next start (start while busy
 * is ignored). rst_n=0 stops an operation.
 * At start: operands unpacked (Fp32Unpack); a subnormal significand normalized (its top 1
 * found by PriorityEncoder, shifted to bit 23 by BarrelShifter, the exponent lowered), so
 * both significands are in [1, 2).
 *  - Divide: when a's significand is below b's it is doubled (the exponent one lower), so the
 *    quotient is in [1, 2); its exponent e_a - e_b + 127 (less 1). Every step compares the
 *    partial remainder R with the divisor d: R >= d gives the quotient bit 1 and R - d; R is
 *    then doubled.
 *  - Square root: the exponent made even (an odd one doubles the significand: m in [1, 4)),
 *    the root's exponent half of it; m << 25 is the radicand, read two bits a step from the
 *    top. Every step appends them to R and compares with T = {root so far, 01}: R >= T gives
 *    the root bit 1 and R - T.
 *  Both compares are one subtraction (BrentKungAdder, 28 bits; no borrow: it fits), its
 *  operands chosen by sqrt (Mux2). After 25 steps the 25 bits (the integer bit and 24 of the
 *  fraction) and a sticky bit (R not 0) go to Fp32Round with the exponent, which makes
 *  subnormals, rounds and flags overflow, underflow and inexact (a root is always normal).
 *  - Special cases, decided at start, the steps run anyway: the default NaN for a NaN
 *    operand, 0 / 0, infinity / infinity, the root of a value below 0 (NV for those and for
 *    a signalling NaN); infinity for x / 0 (DZ when x is finite), infinity / x and sqrt(+inf);
 *    0 for 0 / x, x / infinity, sqrt(+0) and sqrt(-0) (-0).
 * Hybrid (AGENTS.md): the normalizing search and shifts, the exponent sums, the step's
 * subtraction, the compare and the wide selects are library blocks, parts and gates; the
 * state is flip-flops (always_ff), the control and flags glue.
 *
 *   a, b --> Fp32Unpack, PriorityEncoder + BarrelShifter (normalize) --> sig, exp
 *        --> exponents (BrentKungAdder, CarrySaveAdder) --> e_res, special result --> flops
 *   step: R, d or {root, 01}, radicand bits --> Mux2 --> BrentKungAdder R - x --> fits
 *         --> Mux2 (R - x or R), << 1 (divide) --> R; {Q, fits} --> Q
 *   Q, R != 0 --> Fp32Round --> Mux4 (rounded, special) --> result, flags
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module Fp32DivSqrt import Fp32Pkg::*, FpPkg::*; (
    input  wire    clk,
    input  wire    rst_n,       // synchronous reset, active low
    input  wire    start,       // takes the operands while busy is 0
    input  wire    sqrt,        // 1: sqrt(a), 0: a / b
    input  fp32_t  a,
    input  fp32_t  b,           // the divisor; not used by sqrt
    input  rm_e    rm,          // rounding mode
    output wire    busy,
    output wire    done,        // 1 in the last clock of busy
    output fp32_t  result,      // valid after done, until the next start
    output flags_t flags
);
    localparam int P     = FP32_MANT_WIDTH + 1;     // 24: a significand
    localparam int QW    = P + 1;                   // 25: result bits, the integer bit first
    localparam int RW    = 28;                      // the partial remainder and the step
    localparam int XW    = 2 * QW;                  // 50: the radicand
    localparam int EW    = 10;                      // exponents, signed
    localparam int STEPS = QW;
    localparam int CW    = $clog2(STEPS + 1);

    // The operands at start, normalized.
    // Of a and b unpacked only the sign, exp, sig and the classes are used.
    /* verilator lint_off UNUSEDSIGNAL */
    fp32_unpacked_t ua;
    fp32_unpacked_t ub;
    /* verilator lint_on UNUSEDSIGNAL */
    logic [P-1:0]   sig_a;      // a's significand with its top 1 at bit 23
    logic [P-1:0]   sig_b;
    logic [EW-1:0]  exp_a;      // a's exponent, lowered by the normalizing shift
    logic [EW-1:0]  exp_b;

    Fp32Unpack u_unpack_a(.x(a), .u(ua));
    Fp32Unpack u_unpack_b(.x(b), .u(ub));

    Fp32DivSqrtNormalize u_normalize_a(.sig(ua.sig), .exp(ua.exp), .sig_n(sig_a), .exp_n(exp_a));
    Fp32DivSqrtNormalize u_normalize_b(.sig(ub.sig), .exp(ub.exp), .sig_n(sig_b), .exp_n(exp_b));

    // Divide: a's significand doubled when below b's; the exponent e_a - e_b + 127 (less 1)
    // = e_a + ~e_b + 128 (less 1).
    logic           a_ge_b;     // sig_a >= sig_b
    logic [EW-1:0]  e_div_ps;
    logic [EW-1:0]  e_div;
    // Square root: the exponent less 127, made even, halved, plus 127.
    logic           odd;        // e_a - 127 is odd: e_a is even
    logic [EW-1:0]  e_even;     // e_a - 127, less 1 when odd
    logic [EW-1:0]  e_sqrt;
    logic [EW-1:0]  e_res;      // the result's exponent
    // Carries out and the top bit of the shifted carries: not used (sums mod 2^EW, signed).
    /* verilator lint_off UNUSEDSIGNAL */
    logic [EW-1:0]  e_div_sc;
    logic           e_div_co;
    logic           e_even_co;
    logic           e_sqrt_co;
    /* verilator lint_on UNUSEDSIGNAL */

    CmpGe #(.WIDTH(P)) u_cmp_ge_sig(.in1(sig_a), .in2(sig_b), .ge(a_ge_b));
    CarrySaveAdder #(.WIDTH(EW)) u_csa_e_div(
        .in1(exp_a), .in2(~exp_b), .in3(a_ge_b ? EW'(128) : EW'(127)), .ps(e_div_ps),
        .sc(e_div_sc));
    BrentKungAdder #(.WIDTH(EW)) u_adder_e_div(
        .in1(e_div_ps), .in2({e_div_sc[EW-2:0], 1'b0}), .ci(1'b0), .co(e_div_co), .sum(e_div));

    assign odd = !exp_a[0];
    BrentKungAdder #(.WIDTH(EW)) u_adder_e_even(
        .in1(exp_a), .in2(odd ? -EW'(128) : -EW'(127)), .ci(1'b0), .co(e_even_co),
        .sum(e_even));
    BrentKungAdder #(.WIDTH(EW)) u_adder_e_sqrt(
        .in1({e_even[EW-1], e_even[EW-1:1]}), .in2(EW'(127)), .ci(1'b0), .co(e_sqrt_co),
        .sum(e_sqrt));
    Mux2 #(.WIDTH(EW)) u_mux2_e_res(.in0(e_div), .in1(e_sqrt), .sel(sqrt), .out(e_res));

    // Special cases at start.
    logic           nan_now;    // the result is the default NaN
    logic           inf_now;    // an infinity
    logic           zero_now;   // a zero
    logic           nv_now;
    logic           dz_now;
    logic           sign_now;   // the result's sign

    always_comb
        if (sqrt) begin
            nan_now  = ua.nan || (ua.sign && !ua.zero);
            nv_now   = ua.snan || (ua.sign && !ua.zero && !ua.nan);
            inf_now  = ua.inf && !ua.sign;
            zero_now = ua.zero;
            dz_now   = 1'b0;
            sign_now = ua.sign && ua.zero;
        end else begin
            nan_now  = ua.nan || ub.nan || (ua.zero && ub.zero) || (ua.inf && ub.inf);
            nv_now   = ua.snan || ub.snan || (ua.zero && ub.zero) || (ua.inf && ub.inf);
            inf_now  = ua.inf || ub.zero;
            zero_now = ua.zero || ub.inf;
            dz_now   = ub.zero && !ua.zero && !ua.inf && !ua.nan;
            sign_now = ua.sign ^ ub.sign;
        end

    // The state.
    logic [CW-1:0]  count;      // steps left
    logic           op_sqrt;
    rm_e            op_rm;
    logic           res_sign;
    logic [EW-1:0]  res_exp;
    logic           spec_nan;   // the special result taken at start
    logic           spec_inf;
    logic           spec_zero;
    logic           spec_nv;
    logic           spec_dz;
    logic [RW-1:0]  r;          // the partial remainder
    logic [P-1:0]   d;          // the divisor
    logic [QW-1:0]  q;          // the result bits so far
    logic [XW-1:0]  x;          // the radicand bits not used yet, on top
    logic           taken;      // start while not busy

    assign taken = start && !busy;
    assign busy  = count != '0;
    assign done  = count == CW'(1);

    // The starting values: divide R = a's significand (doubled when below b's), square root
    // R = 0; the radicand m << 25 (m = a's significand, doubled for an odd exponent).
    logic [P:0]     r_div;
    logic [RW-1:0]  r_init;
    logic [XW-1:0]  x_init;

    Mux2 #(.WIDTH(P + 1)) u_mux2_r_div(
        .in0({sig_a, 1'b0}), .in1({1'b0, sig_a}), .sel(a_ge_b), .out(r_div));
    assign r_init = RW'(r_div) & {RW{!sqrt}};
    Mux2 #(.WIDTH(XW)) u_mux2_x_init(
        .in0({1'b0, sig_a, {(XW - P - 1){1'b0}}}), .in1({sig_a, {(XW - P){1'b0}}}), .sel(odd),
        .out(x_init));

    // One step: R - d (divide) or {R, two radicand bits} - {Q, 01} (square root).
    logic [RW-1:0]  sq_r;       // R with the next two radicand bits
    logic [RW-1:0]  base;       // what is compared: R or sq_r
    logic [RW-1:0]  sub;        // what is subtracted: d or {Q, 01}
    logic [RW-1:0]  diff;       // base - sub
    logic           fits;       // no borrow
    logic [RW-1:0]  kept;       // diff when it fits, else base
    logic [RW-1:0]  r_next;

    assign sq_r = {r[RW-3:0], x[XW-1 -: 2]};
    Mux2 #(.WIDTH(RW)) u_mux2_base(.in0(r), .in1(sq_r), .sel(op_sqrt), .out(base));
    Mux2 #(.WIDTH(RW)) u_mux2_sub(
        .in0(RW'(d)), .in1(RW'({q, 2'b01})), .sel(op_sqrt), .out(sub));
    BrentKungAdder #(.WIDTH(RW)) u_adder_step(
        .in1(base), .in2(~sub), .ci(1'b1), .co(fits), .sum(diff));
    Mux2 #(.WIDTH(RW)) u_mux2_kept(.in0(base), .in1(diff), .sel(fits), .out(kept));
    Mux2 #(.WIDTH(RW)) u_mux2_r_next(
        .in0({kept[RW-2:0], 1'b0}), .in1(kept), .sel(op_sqrt), .out(r_next));

    // @kb: rtl/lib/numeric/fp32/div_sqrt
    always_ff @(posedge clk)
        if (!rst_n)
            count <= '0;
        else if (taken) begin
            count     <= CW'(STEPS);
            op_sqrt   <= sqrt;
            op_rm     <= rm;
            res_sign  <= sign_now;
            res_exp   <= e_res;
            spec_nan  <= nan_now;
            spec_inf  <= !nan_now && inf_now;
            spec_zero <= !nan_now && !inf_now && zero_now;
            spec_nv   <= nv_now;
            spec_dz   <= dz_now;
            r         <= r_init;
            d         <= sig_b;
            q         <= '0;
            x         <= x_init;
        end else if (busy) begin
            count     <= count - CW'(1);
            r         <= r_next;
            q         <= {q[QW-2:0], fits};
            x         <= {x[XW-3:0], 2'b00};
        end

    // The result.
    fp32_t          rounded;
    // Its NV and DZ (0): not used.
    /* verilator lint_off UNUSEDSIGNAL */
    flags_t         round_flags;
    /* verilator lint_on UNUSEDSIGNAL */
    fp32_t          special;

    Fp32Round #(.SIG_WIDTH(QW + 1), .EXP_WIDTH(EW)) u_round(
        .sign(res_sign), .exp(res_exp), .sig({q, |r}), .rm(op_rm), .result(rounded),
        .flags(round_flags));

    assign special = spec_nan ? FP32_DEFAULT_NAN
                              : {res_sign, {FP32_EXP_WIDTH{spec_inf}}, {FP32_MANT_WIDTH{1'b0}}};
    Mux2 #(.WIDTH($bits(fp32_t))) u_mux2_result(
        .in0(rounded), .in1(special), .sel(spec_nan || spec_inf || spec_zero), .out(result));

    assign flags.nv = spec_nan && spec_nv;
    assign flags.dz = spec_inf && spec_dz;
    assign flags.of = !spec_nan && !spec_inf && !spec_zero && round_flags.of;
    assign flags.uf = !spec_nan && !spec_inf && !spec_zero && round_flags.uf;
    assign flags.nx = !spec_nan && !spec_inf && !spec_zero && round_flags.nx;

endmodule

/* The normalizing of Fp32DivSqrt: a significand's top 1 to bit 23, the exponent lowered by
 * the shift (a subnormal's, 1, becomes 1 - the shift); a normal one passes as it is.
 */
module Fp32DivSqrtNormalize import Fp32Pkg::*; (
    input  fp32_sig_t  sig,
    input  fp32_exp_t  exp,
    output fp32_sig_t  sig_n,
    output logic [9:0] exp_n
);
    localparam int P = FP32_MANT_WIDTH + 1;

    logic [4:0] top;        // the index of sig's top 1
    logic [4:0] lz;         // 23 - top: the shift
    // Not used: a zero significand is a special case.
    /* verilator lint_off UNUSEDSIGNAL */
    logic       nonzero;
    logic       lz_co;
    logic       exp_co;
    /* verilator lint_on UNUSEDSIGNAL */

    PriorityEncoder #(.SIZE(5)) u_priority_encoder(
        .in({{(32 - P){1'b0}}, sig}), .out(top), .valid(nonzero));
    // 23 - top = 23 + ~top + 1.
    BrentKungAdder #(.WIDTH(5)) u_adder_lz(
        .in1(5'd23), .in2(~top), .ci(1'b1), .co(lz_co), .sum(lz));
    BarrelShifter #(.WIDTH(P)) u_shifter(
        .in(sig), .shift_in_bit(1'b0), .shift(lz), .shift_rotate(1'b1), .left_right(1'b1),
        .out(sig_n));
    // exp - lz = exp + ~lz + 1.
    BrentKungAdder #(.WIDTH(10)) u_adder_exp(
        .in1(10'(exp)), .in2(~10'(lz)), .ci(1'b1), .co(exp_co), .sum(exp_n));

endmodule

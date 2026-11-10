/* Fp32 minimum or maximum of a and b, its NaN rule a parameter (RISC-V FMIN.S, FMAX.S;
 * FMINM.S, FMAXM.S of Zfa), hybrid.
 *
 * NAN_RULE (FpPkg::minmax_nan_e) says what a NaN operand does: MINMAX_NUMBER (IEEE 754-2019
 * minimumNumber, maximumNumber; RISC-V FMIN.S, FMAX.S) returns the other operand, and the
 * default NaN when both are NaNs; MINMAX_NAN (IEEE 754-2019 minimum, maximum; Zfa's FMINM.S,
 * FMAXM.S, the minimum of ML frameworks) returns the default NaN. Both order -0 below +0
 * (the minimum of the two zeros is -0, the maximum +0) and flag NV for a signalling NaN.
 * Otherwise Fp32Compare's a < b picks: the minimum is a when a < b, else b; the maximum b
 * when a < b, else a (equal values have equal bits). Hybrid (AGENTS.md): the compare is
 * Fp32Compare, the selects Mux2 and Mux4; the rest is glue.
 *
 *   a, b --> Fp32Compare --> a < b --> Mux2 (a or b)
 *        --> Fp32Unpack x 2 --> NaN, zero --> Mux4 (a or b, zero, default NaN) --> result
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module Fp32MinMax import Fp32Pkg::*, FpPkg::*; #(
    parameter minmax_nan_e NAN_RULE = MINMAX_NUMBER     // what a NaN operand does
)(
    input  fp32_t a,
    input  fp32_t b,
    input  wire   max,          // 1: the maximum, 0: the minimum
    output fp32_t result,
    output logic  nv            // a signalling NaN operand
);
    // Only the classes are used.
    /* verilator lint_off UNUSEDSIGNAL */
    fp32_unpacked_t ua;
    fp32_unpacked_t ub;
    // Of the compare only a < b and the signalling NaN are used.
    logic           eq;
    logic           le;
    logic           unordered;
    /* verilator lint_on UNUSEDSIGNAL */
    logic           lt;         // a < b
    logic           pick_b;     // the result is b
    fp32_t          picked;     // a or b
    logic           zero_res;   // both are zeros: a zero of the rule's sign
    logic           nan_res;    // the result is the default NaN
    fp32_t          zero;

    Fp32Unpack u_unpack_a(.x(a), .u(ua));
    Fp32Unpack u_unpack_b(.x(b), .u(ub));
    Fp32Compare u_compare(.a, .b, .eq, .lt, .le, .unordered, .snan(nv));

    // A NaN operand: the other one (MINMAX_NUMBER) or the default NaN.
    if (NAN_RULE == MINMAX_NUMBER) begin: g_number
        assign nan_res = ua.nan && ub.nan;
        assign pick_b  = ua.nan || (!ub.nan && (max ? lt : !lt));
    end else begin: g_nan
        assign nan_res = ua.nan || ub.nan;
        assign pick_b  = max ? lt : !lt;
    end

    Mux2 #(.WIDTH($bits(fp32_t))) u_mux2_pick(.in0(a), .in1(b), .sel(pick_b), .out(picked));

    assign zero_res = ua.zero && ub.zero;
    assign zero     = {max ? a.sign && b.sign : a.sign || b.sign, {($bits(fp32_t) - 1){1'b0}}};

    // 0: a or b, 1: the zero, 2 and 3: the default NaN.
    Mux4 #(.WIDTH($bits(fp32_t))) u_mux4_result(
        .in0(picked), .in1(zero), .in2(FP32_DEFAULT_NAN), .in3(FP32_DEFAULT_NAN),
        .sel({nan_res, zero_res}), .out(result));

endmodule

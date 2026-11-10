/* Fp32 compare: a == b, a < b, a <= b as IEEE 754 defines them (RISC-V FEQ.S, FLT.S, FLE.S),
 * hybrid.
 *
 * A NaN operand makes the pair unordered: every predicate is 0. -0 equals +0. Otherwise the
 * signs and the magnitudes (the 31 bits below the sign, ordered as integers: CmpEq, CmpGe)
 * decide: a negative a is below a positive b, two positives compare as their magnitudes, two
 * negatives the other way round. The exception is the caller's choice: a quiet compare
 * (FEQ) flags NV for a signalling NaN (snan), a signalling one (FLT, FLE) for any NaN
 * (unordered). Hybrid (AGENTS.md): the 31-bit compares are gates; the rest is glue.
 *
 *   a, b --> Fp32Unpack x 2 --> NaN, zero
 *   a[30:0], b[30:0] --> CmpEq, CmpGe --> |a| == |b|, |a| >= |b|
 *   signs --> eq, lt, le, unordered, snan
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module Fp32Compare import Fp32Pkg::*; (
    input  fp32_t a,
    input  fp32_t b,
    output logic  eq,           // a == b
    output logic  lt,           // a < b
    output logic  le,           // a <= b
    output logic  unordered,    // a NaN operand: NV of a signalling compare
    output logic  snan          // a signalling NaN operand: NV of a quiet compare
);
    localparam int M = $bits(fp32_t) - 1;   // 31: the magnitude

    // Only the classes are used.
    /* verilator lint_off UNUSEDSIGNAL */
    fp32_unpacked_t ua;
    fp32_unpacked_t ub;
    /* verilator lint_on UNUSEDSIGNAL */
    logic           mag_eq;     // |a| == |b|
    logic           mag_ge;     // |a| >= |b|
    logic           both_zero;  // -0 and +0 are equal

    Fp32Unpack u_unpack_a(.x(a), .u(ua));
    Fp32Unpack u_unpack_b(.x(b), .u(ub));

    CmpEq #(.WIDTH(M)) u_cmp_eq(.in1(a[M-1:0]), .in2(b[M-1:0]), .eq(mag_eq));
    CmpGe #(.WIDTH(M)) u_cmp_ge(.in1(a[M-1:0]), .in2(b[M-1:0]), .ge(mag_ge));

    assign unordered = ua.nan || ub.nan;
    assign snan      = ua.snan || ub.snan;
    assign both_zero = ua.zero && ub.zero;

    assign eq = !unordered && (both_zero || (a.sign == b.sign && mag_eq));
    assign lt = !unordered && !both_zero &&
                ((a.sign && !b.sign) || (!a.sign && !b.sign && !mag_ge) ||
                 (a.sign && b.sign && mag_ge && !mag_eq));
    assign le = lt || eq;

endmodule

/* The kernel of fp_diff.c: one case of single-precision operations, compiled twice from this
 * file (fp_diff_hw.c with Zfinx: Mig3's FPU; fp_diff_sw.c without F: SoftFloat), the name
 * KERNEL and TAKE_FLAGS() given by the includer (fp_diff.c includes it without KERNEL:
 * FP_DIFF_OUTS only).
 *
 * a, b, c are fp32 values as bits, i an integer; out gets FP_DIFF_OUTS results as bits:
 * every arithmetic operation, the four fused forms, sqrt, the conversions both ways (C's
 * casts: truncating to an integer), the compares, minimumNumber and maximumNumber, sign
 * injection and absolute value, a chain whose operations use the results right before them
 * (forwarding), a fused form whose addend dies in it (the compiler gives rd rs3's
 * register). flags gets the flags each result raised: TAKE_FLAGS() reads and clears them
 * (fflags, or SoftFloat's flags). Compiled with -ffp-model=strict: the operations round by
 * frm, none is folded or moved across TAKE_FLAGS(), only fmaf fuses.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
#include <stdint.h>

#define FP_DIFF_OUTS 24

#ifdef KERNEL
static inline float fp_diff_f(uint32_t u)
{
    float f;
    __builtin_memcpy(&f, &u, sizeof f);
    return f;
}

static inline uint32_t fp_diff_u(float f)
{
    uint32_t u;
    __builtin_memcpy(&u, &f, sizeof u);
    return u;
}

// @kb: test/design/mig3/fp_diff
// Result n as bits, and the flags it raised. The empty asm after the flags "changes" the
// operands: the next operation can not start before the flags are taken. -ffp-model=strict
// pins most operations to their place, but not all (minimumNumber has no strict form in
// LLVM: FMIN.S and FMAX.S were computed together, both flags taken after FMIN.S).
#define R(n, bits)                                                              \
    do {                                                                        \
        out[n]   = (bits);                                                      \
        flags[n] = TAKE_FLAGS();                                                \
        __asm__ volatile("" : "+r"(a), "+r"(b), "+r"(c), "+r"(t), "+r"(i));     \
    } while (0)

void KERNEL(uint32_t ua, uint32_t ub, uint32_t uc, int32_t i, uint32_t *out,
            uint32_t *flags)
{
    float a = fp_diff_f(ua);
    float b = fp_diff_f(ub);
    float c = fp_diff_f(uc);
    float t = 0.0f;
    (void)TAKE_FLAGS();
    R(0,  fp_diff_u(a + b));
    R(1,  fp_diff_u(a - b));
    R(2,  fp_diff_u(a * b));
    R(3,  fp_diff_u(a / b));
    R(4,  fp_diff_u(__builtin_sqrtf(a)));
    R(5,  fp_diff_u(__builtin_fmaf(a, b, c)));          // FMADD.S
    R(6,  fp_diff_u(__builtin_fmaf(-a, b, c)));         // FNMSUB.S
    R(7,  fp_diff_u(__builtin_fmaf(a, b, -c)));         // FMSUB.S
    R(8,  fp_diff_u(__builtin_fmaf(-a, b, -c)));        // FNMADD.S
    R(9,  (uint32_t)(int32_t)a);                        // FCVT.W.S, rtz
    R(10, (uint32_t)a);                                 // FCVT.WU.S, rtz
    R(11, fp_diff_u((float)i));                         // FCVT.S.W
    R(12, fp_diff_u((float)(uint32_t)i));               // FCVT.S.WU
    R(13, a < b);                                       // FLT.S
    R(14, a <= b);                                      // FLE.S
    R(15, a == b);                                      // FEQ.S
    R(16, fp_diff_u(__builtin_fminimum_numf(a, b)));    // FMIN.S
    R(17, fp_diff_u(__builtin_fmaximum_numf(a, b)));    // FMAX.S
    R(18, fp_diff_u(__builtin_copysignf(a, b)));        // FSGNJ.S
    R(19, fp_diff_u(__builtin_fabsf(c)));               // FSGNJX.S
    // A chain: each operation reads the result right before it.
    t = a * b + c;
    t = __builtin_fmaf(t, c, a);
    R(20, fp_diff_u(t));
    t = t / (b - c);
    R(21, fp_diff_u(t));
    R(22, fp_diff_u(__builtin_sqrtf(__builtin_fabsf(t)) + (float)(i & 0xff)));
    // The result goes back into the addend: rd = rs3 (one register for t).
    t = __builtin_fmaf(a, b, t);
    R(23, fp_diff_u(t));
}
#endif

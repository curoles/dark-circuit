/* Soft-float runtime for RISC-V programs without an FPU, on Berkeley SoftFloat (its RISC-V
 * specialization: canonical NaN 0x7fc00000, tininess after rounding, RISC-V's invalid
 * conversion results).
 *
 * The functions a compiler calls for single-precision float code when the -march has no F
 * (or Zfinx): libgcc's names (__addsf3 ... __floatunsisf: clang and gcc call the same) and
 * the C library's fmaf, sqrtf and fminimum_numf, fmaximum_numf (clang's
 * __builtin_fminimum_numf, IEEE 754-2019 minimumNumber: RISC-V's FMIN.S, FMAX.S, modeled
 * here: a quiet NaN operand gives the other operand, two give the canonical NaN, a
 * signalling NaN raises invalid, -0 is below +0). They round by softfloat_roundingMode and
 * raise softfloat_exceptionFlags (RISC-V's frm and fflags in a soft world: the same
 * encodings); the conversions to integers truncate (C's casts) and raise inexact as
 * FCVT.W.S with rtz does. Programs link with -nostdlib: list this file and SoftFloat's
 * sources (cmake/testfloat.cmake, dc_softfloat_rv32) beside the program's own. The values
 * pass as float in the ilp32 ABI (in integer registers) and are taken apart by memcpy: no
 * float instruction here, whatever the -march.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
#include <stdbool.h>
#include <stdint.h>

#include "platform.h"
#include "internals.h"
#include "specialize.h"
#include "softfloat.h"

static float32_t sf(float x)
{
    float32_t r;
    __builtin_memcpy(&r.v, &x, sizeof r.v);
    return r;
}

static float fl(float32_t x)
{
    float r;
    __builtin_memcpy(&r, &x.v, sizeof r);
    return r;
}

float __addsf3(float a, float b) { return fl(f32_add(sf(a), sf(b))); }
float __subsf3(float a, float b) { return fl(f32_sub(sf(a), sf(b))); }
float __mulsf3(float a, float b) { return fl(f32_mul(sf(a), sf(b))); }
float __divsf3(float a, float b) { return fl(f32_div(sf(a), sf(b))); }

int32_t  __fixsfsi(float a)       { return f32_to_i32_r_minMag(sf(a), true); }
uint32_t __fixunssfsi(float a)    { return f32_to_ui32_r_minMag(sf(a), true); }
float    __floatsisf(int32_t i)   { return fl(i32_to_f32(i)); }
float    __floatunsisf(uint32_t i) { return fl(ui32_to_f32(i)); }

// libgcc's compares: __eqsf2 is 0 when a == b (a quiet compare); __ltsf2 below 0 when
// a < b, __lesf2 at most 0 when a <= b (signalling compares). Unordered: not equal, not less.
int __eqsf2(float a, float b) { return !f32_eq(sf(a), sf(b)); }
int __nesf2(float a, float b) { return !f32_eq(sf(a), sf(b)); }
int __ltsf2(float a, float b) { return f32_lt(sf(a), sf(b)) ? -1 : 1; }
int __lesf2(float a, float b) { return f32_le(sf(a), sf(b)) ? 0 : 1; }
int __gtsf2(float a, float b) { return f32_lt(sf(b), sf(a)) ? 1 : -1; }
int __gesf2(float a, float b) { return f32_le(sf(b), sf(a)) ? 0 : -1; }
int __unordsf2(float a, float b)
{
    return isNaNF32UI(sf(a).v) || isNaNF32UI(sf(b).v);
}

float fmaf(float a, float b, float c) { return fl(f32_mulAdd(sf(a), sf(b), sf(c))); }
float sqrtf(float a)                  { return fl(f32_sqrt(sf(a))); }

// minimumNumber / maximumNumber, as RISC-V's FMIN.S and FMAX.S.
static float32_t min_max(float32_t a, float32_t b, bool max)
{
    bool a_nan = isNaNF32UI(a.v);
    bool b_nan = isNaNF32UI(b.v);
    bool a_less;
    float32_t r;
    if (f32_isSignalingNaN(a) || f32_isSignalingNaN(b))
        softfloat_raiseFlags(softfloat_flag_invalid);
    if (a_nan && b_nan) {
        r.v = defaultNaNF32UI;
        return r;
    }
    if (a_nan)
        return b;
    if (b_nan)
        return a;
    a_less = f32_lt_quiet(a, b) || (f32_eq(a, b) && signF32UI(a.v) && !signF32UI(b.v));
    return (a_less != max) ? a : b;
}

float fminimum_numf(float a, float b) { return fl(min_max(sf(a), sf(b), false)); }
float fmaximum_numf(float a, float b) { return fl(min_max(sf(a), sf(b), true)); }

// The flags raised since the last call, cleared (fflags read and cleared in a soft world).
// A call, not an inline read of softfloat_exceptionFlags: until it emits them, a compiler
// sees soft-float operations as operations, not calls, and may move an inline read of the
// flags across them; a call to another file it does not move them across (-ffp-model=strict).
uint32_t soft_float_take_flags(void)
{
    uint32_t f = softfloat_exceptionFlags;
    softfloat_exceptionFlags = 0;
    return f;
}

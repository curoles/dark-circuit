/* fp_diff.c's kernel compiled with Zfinx: Mig3's FPU (fp_diff_kernel.h); the flags are
 * fflags, read and cleared at once.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
#include <stdint.h>

static inline uint32_t take_fflags(void)
{
    uint32_t f;
    __asm__ volatile("csrrw %0, fflags, zero" : "=r"(f) : : "memory");
    return f;
}

#define KERNEL     fp_kernel_hw
#define TAKE_FLAGS take_fflags
#include "fp_diff_kernel.h"

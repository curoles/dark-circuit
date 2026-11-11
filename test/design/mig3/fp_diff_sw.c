/* fp_diff.c's kernel compiled without F: calls into SoftFloat (fp_diff_kernel.h,
 * sw/riscv/softfloat/soft_float.c); the flags are SoftFloat's, taken by a call
 * (soft_float_take_flags: an inline read would move across the soft-float operations).
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
#include <stdint.h>

uint32_t soft_float_take_flags(void);

#define KERNEL     fp_kernel_sw
#define TAKE_FLAGS soft_float_take_flags
#include "fp_diff_kernel.h"

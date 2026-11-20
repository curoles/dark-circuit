/* The P intrinsics the int8 kernel's P files use (int8_kernel_p.c, int8_kernel_p_rows.c),
 * compiled with P only.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
#ifndef INT8_KERNEL_P_H
#define INT8_KERNEL_P_H

#include <stdint.h>
#include <riscv_packed_simd.h>

// The intrinsic of P-ext-intrinsics.adoc, which clang-23's riscv_packed_simd.h does not have
// yet: rd + the four byte products of rs1 and rs2. A clang that has it fails on this
// definition; then it goes.
static inline int32_t __riscv_pm4adda_i8x4(int32_t rd, int8x4_t rs1, int8x4_t rs2) {
    __asm__("pm4adda.b %0, %1, %2" : "+r"(rd) : "r"((uint32_t)rs1), "r"((uint32_t)rs2));
    return rd;
}

#endif

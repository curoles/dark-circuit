/* The int8 kernel with P (int8_kernel.h), the only file of the program compiled with P: four
 * multiply-adds of bytes per PM4ADDA.B; the requantization is int8_kernel_ref.c's, compiled
 * without P. The loops are plain C here, so clang may use any P instruction it likes in
 * them; the test design_mig3_int8_insns lists the instructions of this file and fails on one
 * that Mig3 does not decode. int8_fc_p_rows is in int8_kernel_p_rows.c (a file of its own:
 * Mig3's binary, and its measured cycles, stay as they were).
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
#include "int8_kernel.h"
#include "int8_kernel_p.h"

void int8_fc_p(const int8_t *x, const int8_t *w, const int32_t *bias, const int8_quant_t *q,
               int8_t *y) {
    const int8x4_t *x4 = (const int8x4_t *)x;
    for (int n = 0; n < INT8_N; n++) {
        const int8x4_t *w4  = (const int8x4_t *)(w + n * INT8_K);
        int32_t         acc = bias[n];
        for (int k = 0; k < INT8_K / 4; k++)
            acc = __riscv_pm4adda_i8x4(acc, x4[k], w4[k]);
        y[n] = int8_requantize(acc, q);
    }
}

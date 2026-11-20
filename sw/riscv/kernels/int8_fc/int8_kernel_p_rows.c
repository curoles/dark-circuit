/* The int8 kernel with P over some rows (int8_kernel.h: int8_fc_p_rows), a core's part when
 * several share the layer (Mig6: four rows a PE); compiled with P, as int8_kernel_p.c. A file
 * of its own, so that programs without it (Mig3's test) keep their code as it was.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
#include "int8_kernel.h"
#include "int8_kernel_p.h"

void int8_fc_p_rows(const int8_t *x, const int8_t *w, const int32_t *bias,
                    const int8_quant_t *q, int8_t *y, int first_row, int n_rows) {
    const int8x4_t *x4 = (const int8x4_t *)x;
    for (int n = first_row; n < first_row + n_rows; n++) {
        const int8x4_t *w4  = (const int8x4_t *)(w + n * INT8_K);
        int32_t         acc = bias[n];
        for (int k = 0; k < INT8_K / 4; k++)
            acc = __riscv_pm4adda_i8x4(acc, x4[k], w4[k]);
        y[n] = int8_requantize(acc, q);
    }
}

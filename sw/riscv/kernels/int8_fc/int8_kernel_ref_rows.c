/* The int8 kernel in plain C over some rows (int8_kernel.h: int8_fc_ref_rows), a core's part
 * when several share the layer (Mig6: four rows a PE, no P); the same loop as int8_fc_ref.
 * A file of its own, so that programs without it (Mig3's test) keep their code as it was.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
#include "int8_kernel.h"

void int8_fc_ref_rows(const int8_t *x, const int8_t *w, const int32_t *bias,
                      const int8_quant_t *q, int8_t *y, int first_row, int n_rows) {
    for (int n = first_row; n < first_row + n_rows; n++) {
        int32_t acc = bias[n];
        for (int k = 0; k < INT8_K; k++)
            acc += (int32_t)x[k] * w[n * INT8_K + k];
        y[n] = int8_requantize(acc, q);
    }
}

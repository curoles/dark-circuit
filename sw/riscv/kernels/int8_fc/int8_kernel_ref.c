/* The int8 kernel's reference and its requantization (int8_kernel.h): plain C, compiled
 * without P.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
#include "int8_kernel.h"

// TFLite's SaturatingRoundingDoublingHighMul: round(a * b / 2^31), saturated.
static int32_t srdhm(int32_t a, int32_t b) {
    if (a == INT32_MIN && b == INT32_MIN)
        return INT32_MAX;
    int64_t ab    = (int64_t)a * b;
    int32_t nudge = ab >= 0 ? (1 << 30) : (1 - (1 << 30));
    return (int32_t)((ab + nudge) / ((int64_t)1 << 31));
}

// TFLite's RoundingDivideByPOT: x / 2^e, rounded to nearest, ties away from zero.
static int32_t rdbp(int32_t x, int e) {
    int32_t mask      = (int32_t)((1u << e) - 1);
    int32_t remainder = x & mask;
    int32_t threshold = (mask >> 1) + (x < 0);
    return (x >> e) + (remainder > threshold);
}

int8_t int8_requantize(int32_t acc, const int8_quant_t *q) {
    int32_t y = rdbp(srdhm(acc, q->multiplier), q->shift) + q->zero_point;
    y = y < q->act_min ? q->act_min : y;
    y = y > q->act_max ? q->act_max : y;
    return (int8_t)y;
}

void int8_fc_ref(const int8_t *x, const int8_t *w, const int32_t *bias, const int8_quant_t *q,
                 int8_t *y) {
    for (int n = 0; n < INT8_N; n++) {
        int32_t acc = bias[n];
        for (int k = 0; k < INT8_K; k++)
            acc += (int32_t)x[k] * w[n * INT8_K + k];
        y[n] = int8_requantize(acc, q);
    }
}

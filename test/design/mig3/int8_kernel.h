/* The int8 kernel of the P line (rtl/design/mig3/p_profile.md): a fully connected layer of
 * 8-bit inputs and weights as TensorFlow Lite Micro runs it, in two versions.
 *
 *   acc[n] = bias[n] + sum over k of x[k] * w[n][k]      (32 bits)
 *   y[n]   = clamp(zero_point + requantize(acc[n]))      (8 bits)
 *
 * requantize is TFLite's MultiplyByQuantizedMultiplier: a rounding doubling high multiply
 * by a Q31 multiplier, then a rounding shift right. Both versions call the same
 * int8_requantize (int8_kernel_ref.c, compiled without P: its 64-bit arithmetic compiled
 * with P becomes RV32 register-pair instructions, which Mig3 does not have), so their
 * outputs must be the same, bit for bit, and they differ only in the dot products.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
#ifndef INT8_KERNEL_H
#define INT8_KERNEL_H

#include <stdint.h>

#define INT8_K 64           // inputs, a multiple of 4
#define INT8_N 16           // outputs

// The layer's quantization: a Q31 multiplier and a right shift (the scale), the output's
// zero point and the activation's range.
typedef struct {
    int32_t multiplier;
    int     shift;
    int32_t zero_point;
    int32_t act_min;
    int32_t act_max;
} int8_quant_t;

// One output: the accumulator requantized, shifted by the zero point and clamped.
int8_t int8_requantize(int32_t acc, const int8_quant_t *q);

// The layer: y[n] for x[INT8_K], w[INT8_N][INT8_K], bias[INT8_N]. Arrays 4-byte aligned.
void int8_fc_ref(const int8_t *x, const int8_t *w, const int32_t *bias, const int8_quant_t *q,
                 int8_t *y);
void int8_fc_p(const int8_t *x, const int8_t *w, const int32_t *bias, const int8_quant_t *q,
               int8_t *y);

#endif

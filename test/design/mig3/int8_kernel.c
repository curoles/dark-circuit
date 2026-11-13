/* The int8 kernel on TbMig3 (int8_kernel.h), judged by the exit status: the layer computed by
 * the plain-C reference (int8_kernel_ref.c, compiled without P) and by the P version
 * (int8_kernel_p.c, compiled with P), on the same random inputs, weights and biases; every
 * output must agree. Three rounds, each with its data and quantization (one with a ReLU: the
 * activation's minimum at the zero point). The clock cycles of each version (rdcycle) are
 * printed (semihosting), round by round. Exit 0 when all outputs agree, else 1.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
#include <stdint.h>

#include "int8_kernel.h"
#include "semihosting/semihosting.h"

#define ROUNDS 3

static int8_t  x[INT8_K]          __attribute__((aligned(4)));
static int8_t  w[INT8_N * INT8_K] __attribute__((aligned(4)));
static int32_t bias[INT8_N];
static int8_t  y_ref[INT8_N];
static int8_t  y_p[INT8_N];

static uint32_t seed = 0x2545f491;

static uint32_t xorshift(void) {
    seed ^= seed << 13;
    seed ^= seed >> 17;
    seed ^= seed << 5;
    return seed;
}

static uint32_t cycles(void) {
    uint32_t c;
    __asm__ volatile("rdcycle %0" : "=r"(c));
    return c;
}

static void put(const char *s) { semihost_write0(s); }

static void put_dec(uint32_t v) {
    char buf[11];
    int  i = 10;
    buf[i] = 0;
    do {
        buf[--i] = (char)('0' + v % 10);
        v /= 10;
    } while (v != 0);
    put(&buf[i]);
}

int main(void) {
    static const int8_quant_t quants[ROUNDS] = {
        {1518500250, 7, -3, -128, 127},     // scale about 0.707 / 2^7
        {1073741824, 5, 10, 10, 127},       // ReLU: the minimum at the zero point
        {2147483647, 9, 0, -128, 127},
    };
    int fail = 0;
    for (int r = 0; r < ROUNDS; r++) {
        for (int k = 0; k < INT8_K; k++)
            x[k] = (int8_t)xorshift();
        for (int i = 0; i < INT8_N * INT8_K; i++)
            w[i] = (int8_t)xorshift();
        for (int n = 0; n < INT8_N; n++)
            bias[n] = (int32_t)(xorshift() % 4096) - 2048;
        uint32_t t0 = cycles();
        int8_fc_ref(x, w, bias, &quants[r], y_ref);
        uint32_t t1 = cycles();
        int8_fc_p(x, w, bias, &quants[r], y_p);
        uint32_t t2 = cycles();
        for (int n = 0; n < INT8_N; n++)
            if (y_ref[n] != y_p[n])
                fail = 1;
        put("int8 kernel round ");
        put_dec((uint32_t)r);
        put(": plain C ");
        put_dec(t1 - t0);
        put(" cycles, P ");
        put_dec(t2 - t1);
        put(fail ? " cycles, MISMATCH\n" : " cycles\n");
    }
    return fail;
}

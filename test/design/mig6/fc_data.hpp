// The data of the int8 layer tests on Mig6 (fc_layer.cpp and the ones after it): the
// generator, the three rounds and the quantizations of Mig3's test
// (test/design/mig3/int8_kernel.c), and the layer's arrays; every hart makes the same data.
// The kernel and its sizes are sw/riscv/kernels/int8_fc's (int8_kernel.h).
//
// @author    Igor Lesik
// @copyright 2026 Igor Lesik, MIT License
#pragma once

#include <stdint.h>

extern "C" {
#include "int8_kernel.h"
}

namespace {

constexpr int FC_ROUNDS = 3;

// The quantizations of Mig3's test, round by round (one with a ReLU).
constexpr int8_quant_t FC_QUANTS[FC_ROUNDS] = {
    {1518500250, 7, -3, -128, 127},     // scale about 0.707 / 2^7
    {1073741824, 5, 10, 10, 127},       // ReLU: the minimum at the zero point
    {2147483647, 9, 0, -128, 127},
};

int8_t  x[INT8_K]          __attribute__((aligned(4)));
int8_t  w[INT8_N * INT8_K] __attribute__((aligned(4)));
int32_t bias[INT8_N];
uint32_t seed = 0x2545f491;             // Mig3's test's

uint32_t xorshift()
{
    seed ^= seed << 13;
    seed ^= seed >> 17;
    seed ^= seed << 5;
    return seed;
}

// The data of a round, the same on every hart (as Mig3's test makes it).
void make_data()
{
    for (int k = 0; k < INT8_K; k++)
        x[k] = static_cast<int8_t>(xorshift());
    for (int i = 0; i < INT8_N * INT8_K; i++)
        w[i] = static_cast<int8_t>(xorshift());
    for (int n = 0; n < INT8_N; n++)
        bias[n] = static_cast<int32_t>(xorshift() % 4096) - 2048;
}

}   // namespace

// The int8 fully connected layer of sw/riscv/kernels/int8_fc on the four PEs of TbMig6, the
// first target of rtl/design/mig6/README.md: 64 inputs, 16 outputs, each PE 4 of them (rows
// 4 * hart .. 4 * hart + 3) in plain C (Mig6 has no P: kb rtl/design/mig6/no_p). One binary
// with the whole layer: every hart makes the same data (the generator and the three rounds
// of Mig3's test, test/design/mig3/int8_kernel.c), so the data is in its local memory
// before the layer starts. A round: hart 0 computes the whole layer alone first (the
// reference, and one PE's time); a barrier; every hart computes its rows and stores its 4
// outputs to the shared memory (one word); a barrier; hart 0 compares the 16 outputs there
// with its reference, bit for bit, and prints one PE's cycles against four PEs' (from the
// first barrier to the second, its view: the slowest PE, the stores and the barrier).
// Every hart prints its rows' cycles. Exit 0 when every output agrees, 1 at a mismatch, 2
// when a barrier's wait (cycle CSR) ends without every hart.
//
// @author    Igor Lesik
// @copyright 2026 Igor Lesik, MIT License

#include <stdint.h>

#include "mig6/mig6_csr_ops.hpp"
#include "mig6/mig6_pma.hpp"
#include "tprintf.h"

extern "C" {
#include "int8_kernel.h"
}

using namespace mig6;

namespace {

constexpr uint32_t N_HARTS  = 4;                // TbMig6's PEs (Mig6NocPkg::N_PES)
constexpr uint32_t ROWS     = INT8_N / N_HARTS; // a PE's outputs
constexpr int      ROUNDS   = 3;
constexpr uint32_t Y_AT     = 0x00;             // the outputs: hart h's word at Y_AT + 4 h
constexpr uint32_t COUNT_AT = 0x40;             // the barriers' counter
constexpr uint32_t WAIT     = 100000;           // clocks a hart waits at a barrier

static_assert(INT8_N % N_HARTS == 0 && ROWS == 4, "four rows a PE: one word of outputs");
static_assert(Y_AT + 4 * N_HARTS <= COUNT_AT, "the outputs before the counter");

// The quantizations of Mig3's test, round by round (one with a ReLU).
constexpr int8_quant_t QUANTS[ROUNDS] = {
    {1518500250, 7, -3, -128, 127},     // scale about 0.707 / 2^7
    {1073741824, 5, 10, 10, 127},       // ReLU: the minimum at the zero point
    {2147483647, 9, 0, -128, 127},
};

int8_t  x[INT8_K]          __attribute__((aligned(4)));
int8_t  w[INT8_N * INT8_K] __attribute__((aligned(4)));
int32_t bias[INT8_N];
int8_t  y_ref[INT8_N];                  // hart 0: the whole layer alone
int8_t  y[INT8_N];                      // this hart's rows
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

// Barrier k (1, 2, ...): the counter only grows, barrier k ends when it reaches N_HARTS k;
// false when the wait (WAIT clocks) ends without every hart.
bool barrier(volatile uint32_t* count, uint32_t k)
{
    __atomic_fetch_add(count, 1u, __ATOMIC_SEQ_CST);
    const uint32_t start = csr::cycle::read();
    while (__atomic_load_n(count, __ATOMIC_ACQUIRE) < N_HARTS * k)
        if (csr::cycle::read() - start > WAIT)
            return false;
    return true;
}

}   // namespace

// extern "C": crt0.S calls main (freestanding, its name would be mangled).
extern "C" int main()
{
    volatile uint32_t* count = pma::shared::at<uint32_t, COUNT_AT>();
    const uint32_t     hart  = csr::mhartid::read();
    const int          first = static_cast<int>(ROWS * hart);
    uint32_t           k     = 0;      // barriers passed
    int                bad   = 0;

    for (int r = 0; r < ROUNDS; r++) {
        make_data();
        uint32_t one = 0;
        if (hart == 0) {
            const uint32_t t = csr::cycle::read();
            int8_fc_ref(x, w, bias, &QUANTS[r], y_ref);
            one = csr::cycle::read() - t;
        }
        if (!barrier(count, ++k))
            return 2;
        const uint32_t t0 = csr::cycle::read();
        int8_fc_ref_rows(x, w, bias, &QUANTS[r], y, first, static_cast<int>(ROWS));
        const uint32_t t1 = csr::cycle::read();
        uint32_t out = 0;
        for (uint32_t i = 0; i < ROWS; i++)
            out |= static_cast<uint32_t>(static_cast<uint8_t>(y[first + i])) << (8 * i);
        *pma::shared::at<uint32_t>(Y_AT + 4 * hart) = out;
        if (!barrier(count, ++k))
            return 2;
        const uint32_t t2 = csr::cycle::read();
        tprintf("fc: round %d hart %u rows %d..%d: %u cycles\n", r, hart, first,
                first + static_cast<int>(ROWS) - 1, t1 - t0);
        if (hart != 0)
            continue;
        for (uint32_t h = 0; h < N_HARTS; h++) {
            const uint32_t got = *pma::shared::at<uint32_t>(Y_AT + 4 * h);
            for (uint32_t i = 0; i < ROWS; i++) {
                const int8_t v = static_cast<int8_t>(got >> (8 * i));
                if (v != y_ref[ROWS * h + i]) {
                    tprintf("fc: round %d output %u is %d, expected %d\n", r, ROWS * h + i,
                            v, y_ref[ROWS * h + i]);
                    bad = 1;
                }
            }
        }
        const uint32_t four = t2 - t0;
        tprintf("fc: round %d: one PE %u cycles, four PEs %u cycles, speedup %u.%02u\n", r, one,
                four, one / four, (100 * one / four) % 100);
    }
    return bad;
}

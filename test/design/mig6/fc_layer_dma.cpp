// The int8 layer of fc_layer.cpp on the four PEs of TbMig6, its data fetched by each PE's DMA
// from the shared memory (chunk 8b, rtl/design/mig6/README.md): the cost of moving the
// weights, against fc_layer's data made in place. A round: hart 0 makes the data (fc_data.hpp)
// and computes the whole layer alone (the reference, one PE's cycles), then stores the
// input, the weights and the biases to the shared memory in their own layout; every hart
// clears its local copy of its part (so only the DMA can bring it back); a barrier; every
// hart fetches its part with three DMA transfers, polled (sw/riscv/drivers/dma.h): the input
// (64 bytes), its 4 rows of weights (256), its 4 biases (16); computes its 4 outputs; stores
// them to the shared memory (one word); a barrier; hart 0 compares the 16 outputs with its
// reference, bit for bit. Every hart prints its fetch's and its compute's cycles; hart 0
// prints one PE's cycles against four PEs' with the fetch (from the first barrier to the
// second, its view). Exit 0 when every output agrees, 1 at a mismatch, 2 when a barrier's
// wait ends without every hart, 3 when a transfer does not end within WAIT clocks.
//
// @author    Igor Lesik
// @copyright 2026 Igor Lesik, MIT License

#include <stdint.h>

#include "mig6/mig6_csr_ops.hpp"
#include "mig6/mig6_pma.hpp"
#include "mig6/mig6_shmem_amo_add_barrier.hpp"
#include "tprintf.h"

#include "fc_data.hpp"

extern "C" {
#include "drivers/dma.h"
}

using namespace mig6;

namespace {

constexpr uint32_t  N_HARTS  = 4;               // TbMig6's PEs (Mig6NocPkg::N_PES)
constexpr uint32_t  ROWS     = INT8_N / N_HARTS; // a PE's outputs
constexpr uint32_t  Y_AT     = 0x00;            // the outputs: hart h's word at Y_AT + 4 h
constexpr uint32_t  COUNT_AT = 0x40;            // the barriers' counter
constexpr uint32_t  X_AT     = 0x100;           // the layer in the shared memory: the input,
constexpr uint32_t  W_AT     = X_AT + INT8_K;   //   the weights (row n at W_AT + INT8_K n),
constexpr uint32_t  BIAS_AT  = W_AT + INT8_N * INT8_K;     // the biases
constexpr uint32_t  WAIT     = 100000;          // clocks a hart waits: a barrier, a transfer
constexpr uintptr_t DMA      = pma::dma::base;  // the PE's DMA, channel 0
constexpr unsigned  CH       = 0;

static_assert(INT8_N % N_HARTS == 0 && ROWS == 4, "four rows a PE: one word of outputs");
static_assert(Y_AT + 4 * N_HARTS <= COUNT_AT && COUNT_AT + 4 <= X_AT, "the words apart");
static_assert(INT8_K % 4 == 0 && BIAS_AT + 4 * INT8_N <= pma::shared::size, "the layer fits");

int8_t y_ref[INT8_N];                   // hart 0: the whole layer alone
int8_t y[INT8_N];                       // this hart's rows

// n bytes (whole words) from local src to the shared memory at offset, by stores.
void store_shared(uint32_t offset, const void* src, uint32_t n)
{
    const uint32_t* s = static_cast<const uint32_t*>(src);
    for (uint32_t i = 0; i < n / 4; i++)
        *pma::shared::at<uint32_t>(offset + 4 * i) = s[i];
}

// n bytes from the shared memory at offset to local dst, by the DMA, polled: false when it
// does not end within WAIT clocks.
bool fetch(uint32_t offset, void* dst, uint32_t n)
{
    dma_setup(DMA, CH, pma::shared::base + offset, reinterpret_cast<uintptr_t>(dst), n);
    dma_run(DMA, CH, 0);
    const uint32_t t = csr::cycle::read();
    while (!dma_done(DMA, CH))
        if (csr::cycle::read() - t > WAIT)
            return false;
    dma_clear(DMA, CH);
    return true;
}

}   // namespace

// extern "C": crt0.S calls main (freestanding, its name would be mangled).
extern "C" int main()
{
    ShmemAmoAddBarrier bar(pma::shared::at<uint32_t, COUNT_AT>(), N_HARTS);
    const uint32_t     hart  = csr::mhartid::read();
    const uint32_t     first = ROWS * hart;
    int8_t* const      my_w  = &w[first * INT8_K];      // my rows of the weights
    int                bad   = 0;

    dma_claim(DMA, CH);
    for (int r = 0; r < FC_ROUNDS; r++) {
        uint32_t one = 0;
        if (hart == 0) {
            make_data();
            const uint32_t t = csr::cycle::read();
            int8_fc_ref(x, w, bias, &FC_QUANTS[r], y_ref);
            one = csr::cycle::read() - t;
            store_shared(X_AT, x, sizeof x);
            store_shared(W_AT, w, sizeof w);
            store_shared(BIAS_AT, bias, sizeof bias);
        }
        // Only the DMA can bring my part back.
        for (uint32_t k = 0; k < INT8_K; k++)
            x[k] = 0;
        for (uint32_t i = 0; i < ROWS * INT8_K; i++)
            my_w[i] = 0;
        for (uint32_t i = 0; i < ROWS; i++)
            bias[first + i] = 0;
        if (!bar.wait(WAIT))
            return 2;

        const uint32_t t0 = csr::cycle::read();
        if (!fetch(X_AT, x, INT8_K) ||
            !fetch(W_AT + first * INT8_K, my_w, ROWS * INT8_K) ||
            !fetch(BIAS_AT + 4 * first, &bias[first], 4 * ROWS))
            return 3;
        const uint32_t t1 = csr::cycle::read();
        int8_fc_ref_rows(x, w, bias, &FC_QUANTS[r], y, static_cast<int>(first),
                         static_cast<int>(ROWS));
        const uint32_t t2 = csr::cycle::read();
        uint32_t out = 0;
        for (uint32_t i = 0; i < ROWS; i++)
            out |= static_cast<uint32_t>(static_cast<uint8_t>(y[first + i])) << (8 * i);
        *pma::shared::at<uint32_t>(Y_AT + 4 * hart) = out;
        if (!bar.wait(WAIT))
            return 2;
        const uint32_t t3 = csr::cycle::read();
        tprintf("fc_dma: round %d hart %u rows %u..%u: fetch %u, compute %u cycles\n", r, hart,
                first, first + ROWS - 1, t1 - t0, t2 - t1);
        if (hart != 0)
            continue;
        for (uint32_t h = 0; h < N_HARTS; h++) {
            const uint32_t got = *pma::shared::at<uint32_t>(Y_AT + 4 * h);
            for (uint32_t i = 0; i < ROWS; i++) {
                const int8_t v = static_cast<int8_t>(got >> (8 * i));
                if (v != y_ref[ROWS * h + i]) {
                    tprintf("fc_dma: round %d output %u is %d, expected %d\n", r, ROWS * h + i,
                            v, y_ref[ROWS * h + i]);
                    bad = 1;
                }
            }
        }
        const uint32_t four = t3 - t0;
        tprintf("fc_dma: round %d: one PE %u cycles, four PEs with the fetch %u cycles, "
                "speedup %u.%02u\n", r, one, four, one / four, (100 * one / four) % 100);
    }
    dma_release(DMA, CH);
    return bad;
}

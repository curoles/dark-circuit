// The int8 fully connected layer of sw/riscv/kernels/int8_fc on the four PEs of TbMig6, the
// first target of rtl/design/mig6/README.md: 64 inputs, 16 outputs, each PE 4 of them (rows
// 4 * hart .. 4 * hart + 3) in plain C (Mig6 has no P: kb rtl/design/mig6/no_p). One binary
// with the whole layer: every hart makes the same data (fc_data.hpp: the generator and the
// three rounds of Mig3's test), so the data is in its local memory
// before the layer starts. A round: hart 0 computes the whole layer alone first (the
// reference, and one PE's time); a barrier; every hart computes its rows and stores its 4
// outputs to the shared memory (one word); a barrier; hart 0 compares the 16 outputs there
// with its reference, bit for bit, and prints one PE's cycles against four PEs' (from the
// first barrier to the second, its view: the slowest PE, the stores and the barrier). The
// barriers are mig6::ShmemAmoAddBarrier.
// Every hart prints its rows' cycles. Exit 0 when every output agrees, 1 at a mismatch, 2
// when a barrier's wait (cycle CSR) ends without every hart.
//
// @author    Igor Lesik
// @copyright 2026 Igor Lesik, MIT License

#include <stdint.h>

#include "mig6/mig6_csr_ops.hpp"
#include "mig6/mig6_pma.hpp"
#include "mig6/mig6_shmem_amo_add_barrier.hpp"
#include "tprintf.h"

#include "fc_data.hpp"

using namespace mig6;

namespace {

constexpr uint32_t N_HARTS  = 4;                // TbMig6's PEs (Mig6NocPkg::N_PES)
constexpr uint32_t ROWS     = INT8_N / N_HARTS; // a PE's outputs
constexpr uint32_t Y_AT     = 0x00;             // the outputs: hart h's word at Y_AT + 4 h
constexpr uint32_t COUNT_AT = 0x40;             // the barriers' counter
constexpr uint32_t WAIT     = 100000;           // clocks a hart waits at a barrier

static_assert(INT8_N % N_HARTS == 0 && ROWS == 4, "four rows a PE: one word of outputs");
static_assert(Y_AT + 4 * N_HARTS <= COUNT_AT, "the outputs before the counter");

int8_t  y_ref[INT8_N];                  // hart 0: the whole layer alone
int8_t  y[INT8_N];                      // this hart's rows

}   // namespace

// extern "C": crt0.S calls main (freestanding, its name would be mangled).
extern "C" int main()
{
    ShmemAmoAddBarrier bar(pma::shared::at<uint32_t, COUNT_AT>(), N_HARTS);
    const uint32_t     hart  = csr::mhartid::read();
    const int          first = static_cast<int>(ROWS * hart);
    int                bad   = 0;

    for (int r = 0; r < FC_ROUNDS; r++) {
        make_data();
        uint32_t one = 0;
        if (hart == 0) {
            const uint32_t t = csr::cycle::read();
            int8_fc_ref(x, w, bias, &FC_QUANTS[r], y_ref);
            one = csr::cycle::read() - t;
        }
        if (!bar.wait(WAIT))
            return 2;
        const uint32_t t0 = csr::cycle::read();
        int8_fc_ref_rows(x, w, bias, &FC_QUANTS[r], y, first, static_cast<int>(ROWS));
        const uint32_t t1 = csr::cycle::read();
        uint32_t out = 0;
        for (uint32_t i = 0; i < ROWS; i++)
            out |= static_cast<uint32_t>(static_cast<uint8_t>(y[first + i])) << (8 * i);
        *pma::shared::at<uint32_t>(Y_AT + 4 * hart) = out;
        if (!bar.wait(WAIT))
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

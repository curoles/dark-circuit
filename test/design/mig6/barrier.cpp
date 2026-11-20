// A barrier on the shared memory, on every PE of TbMig6: each hart stores its stamp (its ID
// with a tag, as the shared memory starts zeroed and 0 is hart 0's ID) into its own word of
// the shared memory, then arrives at the barrier (mig6::ShmemAmoAddBarrier: an amoadd on a
// counter, done by the AtomicUnit next to the shared memory, and loads of the counter until
// every hart has arrived). After the barrier every hart must see every hart's stamp: a PE's
// requests reach the shared memory in order (one request network, one virtual channel), so
// its stamp is there before its add counts. Prints the hart's place in the arrival order
// and the cycles from its store to the barrier's end, "barrier: hart <n> arrived <k> of
// <N>, <c> cycles", and exits with 0; prints what differs and exits with 1 when a stamp is
// missing. The wait has a deadline, WAIT clocks of the cycle CSR; a hart that gives up
// prints how many had arrived and exits with 2.
//
// @author    Igor Lesik
// @copyright 2026 Igor Lesik, MIT License

#include <stdint.h>

#include "mig6/mig6_csr_ops.hpp"
#include "mig6/mig6_pma.hpp"
#include "mig6/mig6_shmem_amo_add_barrier.hpp"
#include "tprintf.h"

using namespace mig6;

namespace {

constexpr uint32_t N_HARTS    = 4;              // TbMig6's PEs (Mig6NocPkg::N_PES)
constexpr uint32_t STAMP_TAG  = 0x57a40000u;    // stamp of hart h: STAMP_TAG | h
constexpr uint32_t COUNT_AT   = 0x00;           // the barrier's counter
constexpr uint32_t STAMPS_AT  = 0x40;           // hart h's stamp: word h from here
constexpr uint32_t WAIT       = 10000;          // clocks a hart waits at the barrier

static_assert(pma::shared::atomics, "the barrier's counter needs AMOs");
static_assert(!pma::shared::cacheable, "the loads of the counter must reach the memory");
static_assert(STAMPS_AT + 4 * N_HARTS <= pma::shared::size, "the stamps fit");

constexpr uint32_t stamp(uint32_t hart) { return STAMP_TAG | hart; }

}   // namespace

// extern "C": crt0.S calls main (freestanding, its name would be mangled).
extern "C" int main()
{
    ShmemAmoAddBarrier bar(pma::shared::at<uint32_t, COUNT_AT>(), N_HARTS);
    const uint32_t     hart  = csr::mhartid::read();
    const uint32_t     start = csr::cycle::read();

    *pma::shared::at<uint32_t>(STAMPS_AT + 4 * hart) = stamp(hart);
    const bool     all    = bar.wait(WAIT);
    const uint32_t cycles = csr::cycle::read() - start;
    if (!all) {
        tprintf("barrier: hart %u gave up after %u cycles, %u of %u arrived\n", hart, cycles,
                bar.arrived(), N_HARTS);
        return 2;
    }

    int missing = 0;
    for (uint32_t h = 0; h < N_HARTS; h++) {
        const uint32_t seen = *pma::shared::at<uint32_t>(STAMPS_AT + 4 * h);
        if (seen != stamp(h)) {
            tprintf("barrier: hart %u sees %08x for hart %u, not %08x\n", hart, seen, h,
                    stamp(h));
            missing++;
        }
    }
    tprintf("barrier: hart %u arrived %u of %u, %u cycles\n", hart, bar.arrived_before() + 1,
            N_HARTS, cycles);
    return missing == 0 ? 0 : 1;
}

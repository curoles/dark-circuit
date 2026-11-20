// Compare-and-swap on the shared memory, on every PE of TbMig6: each hart adds 1 to a
// shared counter N_INCS times with a compare-and-swap loop (__atomic_compare_exchange_n: LR
// and SC, far, decided by the shared memory's exclusive monitor; kb
// rtl/design/mig6/far_lr_sc) and to another N_INCS times with amoadd, then arrives at a
// barrier (mig6::ShmemAmoAddBarrier). After it both counters must be N_HARTS * N_INCS: an
// SC that succeeded on a word another PE wrote since its LR would lose an increment. A
// compare-and-swap on a stack variable (the local memory: the core's own reservation,
// Mig6Atomic) must succeed with the right expected value and fail with a wrong one. Prints
// the hart's retries (a CAS that found the counter changed by another hart) and exits with
// 0; prints what differs and exits with 1, or with 2 when the barrier's wait (cycle CSR)
// ends without every hart.
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

constexpr uint32_t N_HARTS  = 4;                // TbMig6's PEs (Mig6NocPkg::N_PES)
constexpr uint32_t N_INCS   = 20;               // increments of each counter by each hart
constexpr uint32_t CAS_AT   = 0x00;             // the counter of the CAS loops
constexpr uint32_t AMO_AT   = 0x04;             // the counter of the amoadds
constexpr uint32_t COUNT_AT = 0x08;             // the barrier's counter
constexpr uint32_t WAIT     = 20000;            // clocks a hart waits at the barrier

static_assert(pma::shared::reservable && !pma::shared::cacheable,
              "LR/SC on the shared memory are done at the memory");
static_assert(pma::shared::atomics, "the amoadd counter and the barrier need AMOs");

// Add 1 with a compare-and-swap loop; returns the retries (the counter changed between the
// load and the CAS; an SC that fails inside the CAS is retried by the CAS itself).
uint32_t cas_add(volatile uint32_t* p)
{
    uint32_t retries = 0;
    uint32_t old     = *p;
    while (!__atomic_compare_exchange_n(p, &old, old + 1, false, __ATOMIC_SEQ_CST,
                                        __ATOMIC_RELAXED))
        retries++;
    return retries;
}

}   // namespace

// extern "C": crt0.S calls main (freestanding, its name would be mangled).
extern "C" int main()
{
    volatile uint32_t* cas_count = pma::shared::at<uint32_t, CAS_AT>();
    volatile uint32_t* amo_count = pma::shared::at<uint32_t, AMO_AT>();
    ShmemAmoAddBarrier bar(pma::shared::at<uint32_t, COUNT_AT>(), N_HARTS);
    const uint32_t     hart      = csr::mhartid::read();
    int                bad       = 0;

    // The local memory: the core's own reservation.
    uint32_t local    = 5;
    uint32_t expected = 5;
    const bool local_ok  = __atomic_compare_exchange_n(&local, &expected, 6u, false,
                                                       __ATOMIC_SEQ_CST, __ATOMIC_RELAXED);
    expected = 5;
    const bool local_bad = __atomic_compare_exchange_n(&local, &expected, 7u, false,
                                                       __ATOMIC_SEQ_CST, __ATOMIC_RELAXED);
    if (!local_ok || local_bad || local != 6 || expected != 6) {
        tprintf("cas: hart %u local CAS ok %d bad %d, value %u expected %u\n", hart, local_ok,
                local_bad, local, expected);
        bad++;
    }

    uint32_t retries = 0;
    for (uint32_t i = 0; i < N_INCS; i++) {
        retries += cas_add(cas_count);
        __atomic_fetch_add(amo_count, 1u, __ATOMIC_SEQ_CST);
    }
    if (!bar.wait(WAIT)) {
        tprintf("cas: hart %u gave up at the barrier, %u of %u arrived\n", hart, bar.arrived(),
                N_HARTS);
        return 2;
    }
    const uint32_t cas_end = *cas_count;
    const uint32_t amo_end = *amo_count;
    if (cas_end != N_HARTS * N_INCS || amo_end != N_HARTS * N_INCS) {
        tprintf("cas: hart %u counters CAS %u amoadd %u, expected %u\n", hart, cas_end, amo_end,
                N_HARTS * N_INCS);
        bad++;
    }
    tprintf("cas: hart %u counted to %u, %u retries\n", hart, cas_end, retries);
    return bad == 0 ? 0 : 1;
}

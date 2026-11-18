// The semihosting timeout (sw/riscv/semihosting/semihost_timeout.hpp) on every PE of TbMig6:
// SYS_CLOCK answers and does not go back; a wait whose condition is true returns true; a
// wait whose condition stays false returns false once its time is up, with nothing left and
// at least its milliseconds gone by on the clock. Prints the clocks that wait took (TbMig6:
// a centisecond is +clocks_per_cs clocks) and exits with 0, else prints what failed and
// exits with 1.
//
// @author    Igor Lesik
// @copyright 2026 Igor Lesik, MIT License

#include <stdint.h>

#include "mig6/mig6_csr_ops.hpp"
#include "semihost_timeout.hpp"
#include "tprintf.h"

using namespace mig6;

namespace {

constexpr uint32_t WAIT_MS = 20;

}   // namespace

// extern "C": crt0.S calls main (freestanding, its name would be mangled).
extern "C" int main()
{
    const uint32_t hart = csr::mhartid::read();

    const long first  = semihost_clock();
    const long second = semihost_clock();
    if (first < 0 || second < first) {
        tprintf("timeout: hart %u SYS_CLOCK gave %d then %d\n", hart, first, second);
        return 1;
    }

    const semihost::Timeout soon(WAIT_MS);
    if (!soon.wait([] { return true; })) {
        tprintf("timeout: hart %u a true condition timed out\n", hart);
        return 1;
    }

    const uint32_t          start_ms = semihost_now_ms();
    const uint32_t          start    = csr::cycle::read();
    const semihost::Timeout never(WAIT_MS);
    const bool              got      = never.wait([] { return false; });
    const uint32_t          clocks   = csr::cycle::read() - start;
    const uint32_t          gone_ms  = semihost_now_ms() - start_ms;
    if (got || never.remaining_ms() != 0 || gone_ms < WAIT_MS) {
        tprintf("timeout: hart %u false condition: wait %d, left %u ms, %u ms gone\n", hart,
                got, never.remaining_ms(), gone_ms);
        return 1;
    }
    tprintf("timeout: hart %u waited %u ms for %u ms, %u clocks\n", hart, gone_ms, WAIT_MS,
            clocks);
    return 0;
}

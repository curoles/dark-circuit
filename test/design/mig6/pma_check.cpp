// The C++ memory map (sw/riscv/mig6/mig6_pma.hpp) on every PE of TbMig6: the regions and
// pma_of checked when compiled (static_assert), pointers into the shared memory made (not
// used: the PE's network interface comes later), and pma_of of a variable on the stack at
// run time; prints "pma: hart <n> ok" and exits with 0, else prints what differs and exits
// with 1.
//
// @author    Igor Lesik
// @copyright 2026 Igor Lesik, MIT License

#include <stdint.h>

#include "mig6/mig6_csr_ops.hpp"
#include "mig6/mig6_pma.hpp"
#include "tprintf.h"

using namespace mig6;

namespace {

// The map, when compiled.
static_assert(pma::shared::base == 0x80000000u && pma::shared::size == 0x00100000u, "shared");
static_assert(pma::shared::atomics && !pma::shared::cacheable && pma::shared::reservable,
              "shared: AMOs (the barrier), one copy, LR/SC at the memory");
static_assert(pma::shared::target == pma::target_t::net, "shared: through the network");
static_assert(pma::pma_of(0x8000003cu).target == pma::target_t::net, "inside shared");
static_assert(!pma::pma_of(0x80100000u).hit, "just past the shared memory: no region");
static_assert(!pma::pma_of(0x0000fffcu).cacheable && pma::pma_of(0x0000fffcu).reservable,
              "the local memory's last word: a scratchpad, LR/SC the core's own");
static_assert(pma::pma_of(0x0c000000u).io && !pma::pma_of(0x0c000000u).cacheable, "devices");
static_assert(!pma::pma_of(0x00010000u).hit, "just past the local memory: no region");

}   // namespace

// extern "C": crt0.S calls main (freestanding, its name would be mangled).
extern "C" int main()
{
    volatile uint32_t* count = pma::shared::at<uint32_t, 0x40>();
    volatile uint32_t* other = pma::shared::at<uint32_t>(0x44);
    uint32_t           local = 0;
    const uint32_t     where = static_cast<uint32_t>(reinterpret_cast<uintptr_t>(&local));
    const uint32_t     hart  = csr::mhartid::read();

    if (reinterpret_cast<uintptr_t>(count) != 0x80000040u
        || reinterpret_cast<uintptr_t>(other) != 0x80000044u) {
        tprintf("pma: hart %u shared pointers %p %p\n", hart, count, other);
        return 1;
    }
    if (pma::pma_of(where).target != pma::target_t::local) {
        tprintf("pma: hart %u stack variable at %08x is not in local\n", hart, where);
        return 1;
    }
    tprintf("pma: hart %u ok\n", hart);
    return 0;
}

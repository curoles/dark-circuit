// ShmemAmoAddBarrier: a barrier of n harts on a counter in Mig6's shared memory, by
// fetch-and-add. Each arriving hart adds 1 with amoadd (an AMO, done by the AtomicUnit next
// to the shared memory, rtl/design/mig6/README.md), then loads the counter until it reaches
// n times the barriers passed. The counter only grows: barrier k ends at n k arrivals, so no
// hart resets it (a reset races with a fast hart arriving at the next barrier; the textbook
// cure is a sense flag that flips each time, which a growing counter does not need).
//
// What it relies on:
//  - one counter per barrier object, starting at 0 (the shared RAM starts zeroed), used by
//    the same n harts, each waiting at every barrier;
//  - the shared memory is never cached, so the loads see the counter at the memory;
//  - a hart's requests reach the shared memory in order (one request network, one virtual
//    channel), so its stores before wait() are there before its add counts: after the
//    barrier every hart sees every store made before it;
//  - the wait has a deadline in clocks of the hart's own cycle CSR (no semihosting halt in
//    a loop whose cycles a test measures); after a wait that gave up the barrier is broken.
//
//   mig6::ShmemAmoAddBarrier bar(pma::shared::at<uint32_t, COUNT_AT>(), N_HARTS);
//   if (!bar.wait(WAIT))      // arrive, wait for every hart; false when the deadline passes
//       return 2;
//
// Other barriers may come beside it (an AMO swap with a sense flag, a hardware barrier on
// the network): the name says the place and the operation.
//
// @author    Igor Lesik
// @copyright 2026 Igor Lesik, MIT License
#pragma once

#include <stdint.h>

#include "mig6/mig6_csr_ops.hpp"

namespace mig6 {

class ShmemAmoAddBarrier {
  public:
    // counter: a word of the shared memory, 0 before the first wait; n_harts: who waits.
    ShmemAmoAddBarrier(volatile uint32_t* counter, uint32_t n_harts)
        : counter_(counter), n_harts_(n_harts) {}

    // Arrive and wait for every hart, at most wait_clocks: false when the wait ends without
    // them.
    bool wait(uint32_t wait_clocks)
    {
        before_ = __atomic_fetch_add(counter_, 1u, __ATOMIC_SEQ_CST) - n_harts_ * passed_;
        passed_++;
        const uint32_t start = csr::cycle::read();
        while (__atomic_load_n(counter_, __ATOMIC_ACQUIRE) < n_harts_ * passed_)
            if (csr::cycle::read() - start > wait_clocks)
                return false;
        return true;
    }

    // How many harts arrived at the last barrier before this one.
    uint32_t arrived_before() const { return before_; }

    // How many harts have arrived at the last barrier so far (after a wait that gave up).
    uint32_t arrived() const { return *counter_ - n_harts_ * (passed_ - 1); }

  private:
    volatile uint32_t* counter_;
    uint32_t           n_harts_;
    uint32_t           passed_ = 0;     // barriers this hart arrived at
    uint32_t           before_ = 0;
};

}   // namespace mig6

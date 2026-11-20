// ShmemAmoAddBarrier: a barrier of n harts on a counter in Mig6's shared memory, by
// fetch-and-add. Each arriving hart adds 1 with amoadd (an AMO, done by the AtomicUnit next
// to the shared memory, rtl/design/mig6/README.md), then loads the counter until every hart
// has arrived.
//
//   mig6::ShmemAmoAddBarrier bar(pma::shared::at<uint32_t, COUNT_AT>(), N_HARTS);
//   if (!bar.wait(WAIT))      // arrive, wait for every hart; false when the deadline passes
//       return 2;
//
// THE COUNTER NEVER GOES BACK TO 0. It only grows, by one at every arrival, so barrier k
// (the first is 1) ends when the counter reaches n k, not n. With 4 harts and two barriers
// in a row:
//
//   barrier 1: the four amoadds take the counter 0 -> 4; every hart waits for >= 4 * 1
//   barrier 2: the four amoadds take it 4 -> 8;         every hart waits for >= 4 * 2
//
// Waiting for counter >= n at barrier 2 would end at once: the counter is already 4, left
// from barrier 1, before any hart arrives. Each hart counts the barriers it has arrived at
// (passed_, the k above) and waits for n * passed_.
//
// Why not reset the counter to 0 after each barrier: the reset races. Say the last hart to
// arrive at barrier 1 resets it; a fast hart that already left barrier 1 may add for
// barrier 2 just before the reset, and its arrival is wiped out, so barrier 2 waits forever
// for a hart that came; and a hart still loading the counter for barrier 1 may see it drop
// to 0 and keep waiting. The textbook cure is a second word, a sense flag that flips at
// every barrier; a counter that only grows needs neither. The price: the 32-bit counter
// wraps after 2^32 / n barriers (about a billion for 4 harts), more than a program here
// makes.
//
// passed_ needs no atomic: every hart makes its own ShmemAmoAddBarrier, on its own stack in
// its PE's private local memory, and only its one thread uses it (no interrupt handler
// does). The one word several harts change at once is the counter in the shared memory,
// and that one only by amoadd.
//
// What else it relies on:
//  - one counter for one barrier object per hart, 0 before the first wait (the shared RAM
//    starts zeroed: a hart cannot zero it, another may add before that), used by the same
//    n harts, each waiting at every barrier;
//  - the shared memory is never cached, so the loads see the counter at the memory;
//  - a hart's requests reach the shared memory in order (one request network, one virtual
//    channel), so its stores before wait() are there before its add counts: after the
//    barrier every hart sees every store made before it;
//  - the wait has a deadline in clocks of the hart's own cycle CSR (no semihosting halt in
//    a loop whose cycles a test measures); after a wait that gave up the barrier is broken.
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
    // them. The counter only grows: this barrier ends at n_harts * (barriers arrived at).
    bool wait(uint32_t wait_clocks)
    {
        arrived_before_ = __atomic_fetch_add(counter_, 1u, __ATOMIC_SEQ_CST)
                          - n_harts_ * passed_;
        passed_++;
        const uint32_t start = csr::cycle::read();
        while (__atomic_load_n(counter_, __ATOMIC_ACQUIRE) < n_harts_ * passed_)
            if (csr::cycle::read() - start > wait_clocks)
                return false;
        return true;
    }

    // How many harts arrived at the last barrier before this one.
    uint32_t arrived_before() const { return arrived_before_; }

    // How many harts have arrived at the last barrier so far (after a wait that gave up).
    uint32_t arrived() const { return *counter_ - n_harts_ * (passed_ - 1); }

  private:
    volatile uint32_t* counter_;            // in the shared memory: only grows
    uint32_t           n_harts_;
    uint32_t           passed_         = 0; // barriers this hart arrived at: private, no atomic
    uint32_t           arrived_before_ = 0; // harts before this one at the last barrier
};

}   // namespace mig6

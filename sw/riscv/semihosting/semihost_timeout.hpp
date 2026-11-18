/**@file
 * @brief A timeout on the semihosting host's clock, for C++ programs.
 *
 * semihost::Timeout is a deadline fixed when it is made: timeout_ms milliseconds of
 * semihost_now_ms() (SYS_CLOCK by default: real time on QEMU, the testbench's own count in
 * a simulation). remaining_ms() is what is left, 0 when it has expired; wait(condition)
 * polls condition() until it is true or the time is up. Every reading of the clock is a
 * semihosting call (a halt of the core in a simulation), so a loop whose cycles are measured
 * takes its deadline from the cycle CSR instead.
 *
 *     semihost::Timeout timeout(100);
 *     if (!timeout.wait([&] { return *done != 0; }))
 *         return 2;                               // gave up after 100 ms
 *
 * The clock ticks every 10 ms, so the deadline gets one tick of grace: made just before a
 * tick, it would otherwise end up to a tick early. Unsigned arithmetic: the clock may wrap.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
#pragma once

#include <stdint.h>

#include "semihosting.h"

namespace semihost {

class Timeout {
public:
    static constexpr uint32_t DEFAULT_MS = 60000;
    static constexpr uint32_t TICK_MS    = 10;      // SYS_CLOCK's resolution

    explicit Timeout(uint32_t timeout_ms = DEFAULT_MS)
        : limit_ms_(timeout_ms + TICK_MS), start_ms_(semihost_now_ms()) {}

    // Milliseconds left, 0 when the timeout has expired.
    uint32_t remaining_ms() const
    {
        const uint32_t elapsed = semihost_now_ms() - start_ms_;
        return elapsed >= limit_ms_ ? 0 : limit_ms_ - elapsed;
    }

    // Polls condition() until it is true (returns true) or the timeout expires (returns
    // false). A template, not std::function: its headers want exceptions.
    template <typename F>
    bool wait(const F& condition) const
    {
        while (remaining_ms() != 0)
            if (condition())
                return true;
        return condition();
    }

private:
    const uint32_t limit_ms_;   // the timeout with its grace
    const uint32_t start_ms_;
};

}   // namespace semihost

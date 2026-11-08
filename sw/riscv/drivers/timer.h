/* Timer driver: the library's Timer (rtl/lib/block/timer), the RISC-V machine timer at the
 * offsets of SiFive's CLINT: the time mtime and an alarm mtimecmp per hart.
 *
 * base is the Timer's address, from a design's config header (MIG3_TIMER_BASE); hart is the
 * alarm (Mig3 has one: 0). The offsets are as in TimerPkg (rtl/lib/block/timer/timer_pkg.sv).
 *
 * How the hardware works
 *
 * mtime is a 64-bit counter: it counts every tick, a rate the platform gives (Mig3: every
 * clock). mtimecmp[hart] is an absolute time, an alarm. The Timer's interrupt irq[hart] is 1
 * while mtime >= mtimecmp[hart]: a level, not a pulse; it stays 1 until software moves
 * mtimecmp, and an alarm already in the past fires at once (it cannot be missed). irq comes
 * from a flop: it follows the compare one clock later, also after a write of mtimecmp. After
 * reset mtime is 0 and mtimecmp all ones (no alarm). The registers are 64-bit, two 32-bit
 * words, the low word first; RV32 reads and writes them a word at a time:
 *  - mtime: the high word, the low word, the high word again; when the two high words differ
 *    the low word carried in between: read again (timer_mtime).
 *  - mtimecmp: the low word all ones, the high word, then the low word, so that no value in
 *    between is an alarm in the past (timer_set).
 *
 * The rule when its interrupt goes through a PLIC (Mig3: source MIG3_TIMER_SOURCE)
 *
 * A PLIC source is level-triggered: if the Timer's line is still 1 when the handler completes
 * the interrupt, the source is pending again and the interrupt comes a second time. The line
 * drops one clock after the Timer takes the write that moves mtimecmp, but a complete stored
 * right after that write reaches the PLIC in that very clock (the stores leave the core one
 * per clock):
 *
 *   clock  t     the Timer takes the write of mtimecmp     irq still 1
 *          t+1   the PLIC takes the complete               irq drops: too late, pending again
 *
 * So the handler reads the Timer back after the write and completes after the read:
 * timer_rearm and timer_off do the write and the read. The read is answered only after the
 * Timer took the write (requests to one device stay in order) and the complete leaves the
 * core only after the answer, so by then the line has dropped. Read the device itself, not
 * another one: an interconnect keeps the order of requests to one target only. The same rule
 * holds for every level-triggered device behind the PLIC.
 *
 * Handlers also tolerate a spurious entry: if the alarm is not due (timer_due is 0), complete
 * and return. The RISC-V privileged spec lets the timer's interrupt lag a write of mtimecmp,
 * so software written for this timer should expect one now and then (a later core may wire
 * irq straight to the hart's mtip, without a PLIC).
 *
 *   void handler(void)                                 // the interrupt of the PLIC
 *   {
 *       uint32_t id = plic_claim(PLIC);
 *       if (id == TIMER_SOURCE && timer_due(TIMER, 0)) {
 *           ...                                        // the periodic work
 *           timer_rearm(TIMER, 0, PERIOD);             // moves mtimecmp, reads it back
 *       }
 *       plic_complete(PLIC, id);                       // after the read: the line dropped
 *   }
 *
 * Why: kb rtl/design/mig3/timer, kb rtl/lib/block/timer/design.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
#pragma once

#include <stdint.h>

#define TIMER_MTIMECMP  0x4000u     // + 8 * hart: the low word; the high word + 4
#define TIMER_MTIME     0xbff8u     // the low word; the high word + 4

static inline volatile uint32_t *timer_reg(uintptr_t base, uintptr_t offset)
{
    return (volatile uint32_t *)(base + offset);
}

// The time: high, low, high again until the high word holds (the low word may carry).
static inline uint64_t timer_mtime(uintptr_t base)
{
    uint32_t hi;
    uint32_t lo;
    do {
        hi = *timer_reg(base, TIMER_MTIME + 4u);
        lo = *timer_reg(base, TIMER_MTIME);
    } while (hi != *timer_reg(base, TIMER_MTIME + 4u));
    return ((uint64_t)hi << 32) | lo;
}

// The alarm of hart (it changes only when software writes it).
static inline uint64_t timer_cmp(uintptr_t base, unsigned hart)
{
    uintptr_t cmp = TIMER_MTIMECMP + 8u * hart;
    uint32_t  hi  = *timer_reg(base, cmp + 4u);
    uint32_t  lo  = *timer_reg(base, cmp);
    return ((uint64_t)hi << 32) | lo;
}

// Set the alarm: the low word all ones first, so that no value in between is in the past.
static inline void timer_set(uintptr_t base, unsigned hart, uint64_t when)
{
    uintptr_t cmp = TIMER_MTIMECMP + 8u * hart;
    *timer_reg(base, cmp)      = 0xffffffffu;
    *timer_reg(base, cmp + 4u) = (uint32_t)(when >> 32);
    *timer_reg(base, cmp)      = (uint32_t)when;
}

// The alarm is due: mtime has reached mtimecmp (0: a spurious entry, ignore it).
static inline int timer_due(uintptr_t base, unsigned hart)
{
    return timer_mtime(base) >= timer_cmp(base, hart);
}

// The next alarm, period ticks after the one due, then a read of the Timer: when it returns,
// the Timer's line has dropped and the handler may complete at the PLIC (see above).
static inline void timer_rearm(uintptr_t base, unsigned hart, uint64_t period)
{
    timer_set(base, hart, timer_cmp(base, hart) + period);
    (void)*timer_reg(base, TIMER_MTIMECMP + 8u * hart);
}

// No alarm (the high word all ones), then a read of the Timer, as timer_rearm.
static inline void timer_off(uintptr_t base, unsigned hart)
{
    *timer_reg(base, TIMER_MTIMECMP + 8u * hart + 4u) = 0xffffffffu;
    (void)*timer_reg(base, TIMER_MTIMECMP + 8u * hart);
}

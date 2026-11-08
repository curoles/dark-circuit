/* PLIC driver: the RISC-V Platform-Level Interrupt Controller (riscv-plic-spec, the library's
 * rtl/lib/block/plic), the calls a program needs for context 0, the hart's machine mode.
 *
 * base is the PLIC's address, from a design's config header (MIG3_PLIC_BASE). The offsets are
 * the spec's, as in PlicPkg (rtl/lib/block/plic/plic_pkg.sv). A source k (1 and up) has a
 * priority (0: never), an enable bit for the context and a pending bit; the context has a
 * threshold: a pending, enabled source with a priority above it raises the context's
 * interrupt (Mig3: meip, a machine external interrupt, mcause 0x8000000b). The handler claims
 * (the ID of the source, 0 if none is pending), serves the device, then completes the ID.
 *
 * Level-triggered sources (Mig3: all): a source whose line is still high when its interrupt
 * is completed is pending again at once, a second interrupt. Before plic_complete, make sure
 * the device has dropped its line: read the device back after the write that clears it (a
 * write to a device can land later than the complete; timer.h shows it for the Timer).
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
#pragma once

#include <stdint.h>

#define PLIC_PRIORITY   0x000000u   // + 4 * source
#define PLIC_PENDING    0x001000u   // + 4 * word of 32 sources
#define PLIC_ENABLE     0x002000u   // context 0: + 4 * word of 32 sources
#define PLIC_THRESHOLD  0x200000u   // context 0
#define PLIC_CLAIM      0x200004u   // context 0: a read claims, a write completes

static inline volatile uint32_t *plic_reg(uintptr_t base, uintptr_t offset)
{
    return (volatile uint32_t *)(base + offset);
}

static inline void plic_set_priority(uintptr_t base, unsigned source, uint32_t priority)
{
    *plic_reg(base, PLIC_PRIORITY + 4u * source) = priority;
}

// Enable source for context 0 (the other sources of its word keep their bits).
static inline void plic_enable(uintptr_t base, unsigned source)
{
    volatile uint32_t *word = plic_reg(base, PLIC_ENABLE + 4u * (source / 32u));
    *word |= 1u << (source % 32u);
}

static inline void plic_set_threshold(uintptr_t base, uint32_t threshold)
{
    *plic_reg(base, PLIC_THRESHOLD) = threshold;
}

// Claim: the ID of the highest-priority pending source, 0 if none.
static inline uint32_t plic_claim(uintptr_t base)
{
    return *plic_reg(base, PLIC_CLAIM);
}

// Complete a claimed ID: after the device has dropped its line (see above).
static inline void plic_complete(uintptr_t base, uint32_t id)
{
    *plic_reg(base, PLIC_CLAIM) = id;
}

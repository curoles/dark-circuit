/* DMA driver: the library's DmaSifive (rtl/lib/block/dma/dma_sifive), SiFive's platform DMA
 * (PDMA): its register map, so code written for the FU540's PDMA (Linux's sf-pdma) works too.
 *
 * base is the DMA's address, from a design's config header (MIG3_DMA_BASE); a channel's
 * registers are at base + 0x1000 * ch. The offsets and bits are as in DmaSifivePkg
 * (rtl/lib/block/dma/dma_sifive/dma_sifive_pkg.sv).
 *
 * How the hardware works
 *
 * A channel copies NextBytes bytes from NextSource to NextDestination, any alignment, in
 * transactions of up to a memory beat each; the channels share one mover, round-robin.
 *  - claim: setting it (0 to 1) clears the Next registers, done and error; it can be cleared
 *    only while run is 0 (dma_claim, dma_release).
 *  - run: writing 1 starts a transfer from the Next registers (copied into Exec); the
 *    hardware clears run at the end, unless NextConfig's repeat starts it again; writing 0
 *    stops it after the transaction in flight (dma_stop).
 *  - done: set at the end of every transfer, cleared by software (dma_clear); with doneIE
 *    it is an interrupt (Mig3: PLIC source MIG3_DMA_DONE_SOURCE(ch)), a level like done.
 *  - Exec registers: the transfer going on: ExecBytes the bytes left (dma_left).
 *  - error: set when a transfer gets a bus error (none yet on Mig3).
 * 64-bit registers are two words, the low one first; RV32 writes the high word 0.
 *
 * The rules for software
 *
 *  - Memory and device order (fences): the DMA reads memory itself. Before run, the data a
 *    program stored must be in memory: fence w,o (stores before the device write) in
 *    dma_run. After done, the DMA's writes are in memory, but the program must read them
 *    after it read done: fence i,r (the device read before the memory reads) in dma_done.
 *    Mig3 keeps both orders anyway (one path, in order); a core with a write buffer or out of
 *    order execution needs them.
 *  - Caches: the DMA writes memory, not the caches. A destination the program has loaded
 *    before may be in the data cache, stale: invalidate it (Zicbom cbo.inval, cbo.h) before reading
 *    it, or read only buffers not loaded before. Mig3's data cache writes through, so a
 *    source written by the program is in memory (no clean needed).
 *  - The interrupt (PLIC): done is a level; a handler clears it with dma_clear (the write,
 *    then a read-back of the DMA, as timer.h and uart.h explain) before it completes.
 *
 *   dma_claim(DMA, ch);
 *   dma_setup(DMA, ch, src, dst, len);
 *   dma_run(DMA, ch, 0);                      // fence w,o, then run
 *   while (!dma_done(DMA, ch))                // fence i,r once done
 *       if (late()) ...;                      // a deadline: the caller's clock (timer.h)
 *   dma_release(DMA, ch);
 *
 * Why: kb rtl/design/mig3/dma, kb rtl/lib/block/dma/design.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
#pragma once

#include <stdint.h>

#define DMA_CHANNEL     0x1000u     // a channel's registers: base + DMA_CHANNEL * ch
#define DMA_CONTROL     0x000u
#define DMA_NEXT_CONFIG 0x004u
#define DMA_NEXT_BYTES  0x008u      // the low word; the high word + 4
#define DMA_NEXT_DST    0x010u
#define DMA_NEXT_SRC    0x018u
#define DMA_EXEC_CONFIG 0x104u      // read only
#define DMA_EXEC_BYTES  0x108u
#define DMA_EXEC_DST    0x110u
#define DMA_EXEC_SRC    0x118u

#define DMA_CLAIM       (1u << 0)   // Control
#define DMA_RUN         (1u << 1)
#define DMA_DONE_IE     (1u << 14)
#define DMA_ERROR_IE    (1u << 15)
#define DMA_DONE        (1u << 30)
#define DMA_ERROR       (1u << 31)
#define DMA_REPEAT      (1u << 2)   // NextConfig

static inline volatile uint32_t *dma_reg(uintptr_t base, unsigned ch, uintptr_t offset)
{
    return (volatile uint32_t *)(base + DMA_CHANNEL * ch + offset);
}

// Claim channel ch: its Next registers, done and error cleared.
static inline void dma_claim(uintptr_t base, unsigned ch)
{
    *dma_reg(base, ch, DMA_CONTROL) = DMA_CLAIM;
}

// The next transfer: len bytes from src to dst (one shot).
static inline void dma_setup(uintptr_t base, unsigned ch, uintptr_t src, uintptr_t dst,
                             uint32_t len)
{
    *dma_reg(base, ch, DMA_NEXT_SRC)       = (uint32_t)src;
    *dma_reg(base, ch, DMA_NEXT_SRC + 4)   = 0;
    *dma_reg(base, ch, DMA_NEXT_DST)       = (uint32_t)dst;
    *dma_reg(base, ch, DMA_NEXT_DST + 4)   = 0;
    *dma_reg(base, ch, DMA_NEXT_BYTES)     = len;
    *dma_reg(base, ch, DMA_NEXT_BYTES + 4) = 0;
    *dma_reg(base, ch, DMA_NEXT_CONFIG)    = 0;
}

// Start the transfer set up; ie: also the done interrupt. The program's stores first.
static inline void dma_run(uintptr_t base, unsigned ch, int ie)
{
    __asm__ volatile("fence w, o" ::: "memory");
    *dma_reg(base, ch, DMA_CONTROL) = DMA_CLAIM | DMA_RUN | (ie ? DMA_DONE_IE : 0);
}

// 1 when the transfer is done (then the DMA's writes are in memory and ordered before the
// program's reads that follow), 0 while it runs.
static inline int dma_done(uintptr_t base, unsigned ch)
{
    if (!(*dma_reg(base, ch, DMA_CONTROL) & DMA_DONE))
        return 0;
    __asm__ volatile("fence i, r" ::: "memory");
    return 1;
}

// Clear done and error (and their interrupts), the rest of Control as it reads (run is
// already 0 after a one-shot transfer; a repeating one keeps running), as Linux's driver
// does; then a read-back: when it returns the interrupt line has dropped.
static inline void dma_clear(uintptr_t base, unsigned ch)
{
    uint32_t c = *dma_reg(base, ch, DMA_CONTROL);
    *dma_reg(base, ch, DMA_CONTROL) = c & ~(DMA_DONE | DMA_ERROR);
    (void)*dma_reg(base, ch, DMA_CONTROL);
}

// Stop a transfer after its transaction in flight.
static inline void dma_stop(uintptr_t base, unsigned ch)
{
    uint32_t c = *dma_reg(base, ch, DMA_CONTROL);
    *dma_reg(base, ch, DMA_CONTROL) = c & ~DMA_RUN;
}

// The bytes the transfer still has to move (0 when done).
static inline uint32_t dma_left(uintptr_t base, unsigned ch)
{
    return *dma_reg(base, ch, DMA_EXEC_BYTES);
}

// Release the channel (run must be 0: claim stays while run is 1).
static inline void dma_release(uintptr_t base, unsigned ch)
{
    *dma_reg(base, ch, DMA_CONTROL) = 0;
}

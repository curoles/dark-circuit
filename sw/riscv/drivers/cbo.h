/* Cache-block operations (Zicbom): cbo.clean, cbo.flush and cbo.inval on the cache block
 * that holds an address, and on every block of a buffer. Code that uses them is built with
 * _zicbom in -march.
 *
 * block is the cache-block size in bytes, a power of 2, from a design's config header
 * (MIG3_CBO_BLOCK_SIZE: a line of Mig3's data cache).
 *
 * How the hardware works
 *
 *  - cbo.inval: the caches drop the block, so a later load reads memory. Stores that are
 *    only in a cache are lost; Mig3's data cache writes through, so it holds none.
 *  - cbo.clean: a cache writes the block to memory when it is dirty, and keeps it; a
 *    write-through cache (Mig3's) has nothing to write.
 *  - cbo.flush: clean, then inval.
 *  - Each goes down through every level of caches (Mig3: one) as a write of no bytes; the
 *    core does not wait for it. Mig3 keeps its order with the loads and stores around it
 *    (one path, in order).
 *
 * The rules for software
 *
 *  - A buffer another agent wrote (the DMA): cbo_inval_range over it after the agent is done
 *    (dma_done) and before reading it. A buffer the program wrote for another agent to read:
 *    cbo_clean_range before starting the agent (needed with a write-back cache).
 *  - Blocks are whole: an inval drops every byte of a block, also those of other data
 *    in it (with a write-back cache their stores are lost). Align such buffers to the block
 *    size, or use cbo_flush_range.
 *
 *   dma_run(DMA, ch, 0);
 *   while (!dma_done(DMA, ch))
 *       ...;
 *   cbo_inval_range(buf, len, MIG3_CBO_BLOCK_SIZE);
 *   ... loads of buf see the DMA's data ...
 *
 * Why: kb rtl/design/mig3/cbo, kb rtl/lib/block/cache/cbo.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
#pragma once

#include <stdint.h>

// The block that holds p: written to memory when dirty, kept.
static inline void cbo_clean(const volatile void *p)
{
    __asm__ volatile("cbo.clean (%0)" : : "r"(p) : "memory");
}

// The block that holds p: written to memory when dirty, dropped.
static inline void cbo_flush(const volatile void *p)
{
    __asm__ volatile("cbo.flush (%0)" : : "r"(p) : "memory");
}

// The block that holds p: dropped.
static inline void cbo_inval(const volatile void *p)
{
    __asm__ volatile("cbo.inval (%0)" : : "r"(p) : "memory");
}

// The address of the block that holds p.
static inline uintptr_t cbo_first(const volatile void *p, uint32_t block)
{
    return (uintptr_t)p & ~(uintptr_t)(block - 1);
}

// Every block of the buffer of len bytes at p (none when len is 0).
static inline void cbo_clean_range(const volatile void *p, uint32_t len, uint32_t block)
{
    for (uintptr_t a = cbo_first(p, block); a < (uintptr_t)p + len; a += block)
        cbo_clean((const volatile void *)a);
}

static inline void cbo_flush_range(const volatile void *p, uint32_t len, uint32_t block)
{
    for (uintptr_t a = cbo_first(p, block); a < (uintptr_t)p + len; a += block)
        cbo_flush((const volatile void *)a);
}

static inline void cbo_inval_range(const volatile void *p, uint32_t len, uint32_t block)
{
    for (uintptr_t a = cbo_first(p, block); a < (uintptr_t)p + len; a += block)
        cbo_inval((const volatile void *)a);
}

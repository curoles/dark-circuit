/* Test of Zicbom on Mig3 with its DMA and the driver sw/riscv/drivers/cbo.h (TbMig3, judged
 * by the exit status): the DMA overwrites a buffer the data cache holds; loads see the old
 * words until cbo.flush or cbo.inval drops their lines, then the DMA's; cbo.clean drops
 * nothing (Mig3's data cache writes through: nothing to write back, the old copy stays).
 *
 * The program stores the old words into buf and the new ones into src (memory has both: the
 * data cache allocates on loads only), loads buf (its lines into the data cache), lets the
 * DMA copy src over buf (channel 0, polled, a deadline on the Timer's mtime) and loads buf
 * again: every word old or new, and some old (stale). cbo.clean over buf: the same words
 * stale. cbo.flush over its first half, cbo.inval over its second by the last byte of each
 * block (a CBO names its block by any byte in it): every word new.
 * The retire check lets a word the DMA wrote load old or new until a CBO drops its block
 * (kb rtl/design/mig3/cbo).
 * Exit 0 when all is right; 2 the deadline passed, 3 a word neither old nor new, 4 no word
 * stale (the test would show nothing), 5 cbo.clean changed what loads see, 6 a word old
 * after cbo.flush or cbo.inval.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
#include <stdint.h>

#include "mig3_config.h"
#include "drivers/cbo.h"
#include "drivers/dma.h"
#include "drivers/timer.h"

#define WORDS   16                  // 64 bytes: 8 blocks of Mig3's 8 bytes
#define WRONG   (WORDS + 1)         // stale(): a word neither old nor new
#define WAIT    50000u              // clocks the DMA may take

static uint32_t buf[WORDS] __attribute__((aligned(MIG3_CBO_BLOCK_SIZE)));
static uint32_t src[WORDS];

static uint32_t old_word(unsigned i)
{
    return 0x01d00000u + i;
}

static uint32_t new_word(unsigned i)
{
    return 0x0ee00000u + i;
}

// Loads every word of buf: how many are old, or WRONG.
static unsigned stale(void)
{
    volatile uint32_t *v = buf;
    unsigned n = 0;
    for (unsigned i = 0; i < WORDS; i++) {
        uint32_t w = v[i];
        if (w == old_word(i))
            n++;
        else if (w != new_word(i))
            return WRONG;
    }
    return n;
}

int main(void)
{
    volatile uint32_t *v = buf;
    for (unsigned i = 0; i < WORDS; i++) {
        v[i]   = old_word(i);
        src[i] = new_word(i);
    }
    if (stale() != WORDS)                           // the lines into the data cache
        return 3;

    dma_claim(MIG3_DMA_BASE, 0);
    dma_setup(MIG3_DMA_BASE, 0, (uintptr_t)src, (uintptr_t)buf, sizeof buf);
    dma_run(MIG3_DMA_BASE, 0, 0);
    uint64_t deadline = timer_mtime(MIG3_TIMER_BASE) + WAIT;
    while (!dma_done(MIG3_DMA_BASE, 0))
        if (timer_mtime(MIG3_TIMER_BASE) > deadline)
            return 2;
    dma_release(MIG3_DMA_BASE, 0);

    unsigned n = stale();
    if (n == WRONG)
        return 3;
    if (n == 0)
        return 4;
    cbo_clean_range(buf, sizeof buf, MIG3_CBO_BLOCK_SIZE);
    if (stale() != n)
        return 5;
    cbo_flush_range(buf, sizeof buf / 2, MIG3_CBO_BLOCK_SIZE);
    for (unsigned b = sizeof buf / 2; b < sizeof buf; b += MIG3_CBO_BLOCK_SIZE)
        cbo_inval((volatile uint8_t *)buf + b + MIG3_CBO_BLOCK_SIZE - 1);
    if (stale() != 0)
        return 6;
    return 0;
}

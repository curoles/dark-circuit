/* Test of the DMA of Mig3 and its driver sw/riscv/drivers/dma.h (TbMig3, judged by the exit
 * status): every channel copies at once, from the program's buffers to buffers the program
 * never loaded before (so they are not in the data cache, and loads after the DMA see what
 * it wrote: no cbo.inval needed here).
 *
 * The program fills the sources with stores (the data cache writes through: memory has
 * them), sets up each channel with its own length (1 to 157 bytes) and alignments of source
 * and destination, and runs them all; channels 0 to 2 are polled with dma_done, channel 3
 * ends by its done interrupt through the PLIC (a handler: claim, dma_clear with its
 * read-back, complete). The waits have a deadline on the Timer's mtime (clocks on Mig3).
 * Then every destination byte must be its source byte, and the bytes before and after each
 * destination still 0 (crt0 cleared them). Exit 0 when all is right; 2 a deadline passed,
 * 3 a byte is wrong, 4 the interrupt was not as expected.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
#include <stdint.h>

#include "mig3_config.h"
#include "drivers/dma.h"
#include "drivers/plic.h"
#include "drivers/timer.h"

#define N       MIG3_DMA_CHANNELS
#define SIZE    160
#define GUARD   8                   // bytes before each destination that stay 0
#define IRQ_CH  3                   // the channel that ends by its interrupt
#define WAIT    50000u              // clocks the DMA may take

static uint8_t src[N][SIZE + 8];
static uint8_t dst[N][GUARD + 8 + SIZE + 8];    // .bss: cleared by stores, never loaded

_Static_assert(N == 4, "the tables below are for 4 channels");
static const uint32_t len_of[4]  = {1, 7, 100, 157};
static const unsigned src_off[4] = {0, 3, 5, 1};
static const unsigned dst_off[4] = {0, 6, 2, 7};

static volatile unsigned irqs;      // done interrupts of IRQ_CH
static volatile unsigned wrong;     // claims of another ID, or with done not set

__attribute__((interrupt("machine"))) static void handler(void)
{
    uint32_t id = plic_claim(MIG3_PLIC_BASE);
    if (id == MIG3_DMA_DONE_SOURCE(IRQ_CH) && dma_done(MIG3_DMA_BASE, IRQ_CH)) {
        irqs++;
        dma_clear(MIG3_DMA_BASE, IRQ_CH);           // the write, then the read-back
    } else {
        wrong++;
    }
    plic_complete(MIG3_PLIC_BASE, id);
}

static uint8_t pattern(unsigned c, unsigned i)
{
    return (uint8_t)(c * 37u + i * 11u + 1u);
}

int main(void)
{
    for (unsigned c = 0; c < N; c++)
        for (unsigned i = 0; i < SIZE + 8; i++)
            src[c][i] = pattern(c, i);

    plic_set_priority(MIG3_PLIC_BASE, MIG3_DMA_DONE_SOURCE(IRQ_CH), 1);
    plic_enable(MIG3_PLIC_BASE, MIG3_DMA_DONE_SOURCE(IRQ_CH));
    __asm__ volatile("csrw mtvec, %0" : : "r"(handler));    // direct mode
    __asm__ volatile("csrs mie, %0" : : "r"(1u << 11));     // MEIE
    __asm__ volatile("csrsi mstatus, 8");                   // MIE

    for (unsigned c = 0; c < N; c++) {
        dma_claim(MIG3_DMA_BASE, c);
        dma_setup(MIG3_DMA_BASE, c, (uintptr_t)&src[c][src_off[c]],
                  (uintptr_t)&dst[c][GUARD + dst_off[c]], len_of[c]);
    }
    for (unsigned c = 0; c < N; c++)
        dma_run(MIG3_DMA_BASE, c, c == IRQ_CH);

    uint64_t deadline = timer_mtime(MIG3_TIMER_BASE) + WAIT;
    for (unsigned c = 0; c < N; c++) {
        if (c == IRQ_CH)
            continue;
        while (!dma_done(MIG3_DMA_BASE, c))
            if (timer_mtime(MIG3_TIMER_BASE) > deadline)
                return 2;
    }
    while (irqs == 0)
        if (timer_mtime(MIG3_TIMER_BASE) > deadline)
            return 2;

    for (unsigned c = 0; c < N; c++) {
        unsigned first = GUARD + dst_off[c];
        for (unsigned i = 0; i < sizeof dst[c]; i++) {
            uint8_t want = (i >= first && i < first + len_of[c])
                           ? pattern(c, src_off[c] + (i - first)) : 0;
            if (dst[c][i] != want)
                return 3;
        }
    }
    if (irqs != 1 || wrong != 0 || (*dma_reg(MIG3_DMA_BASE, IRQ_CH, DMA_CONTROL) & DMA_DONE))
        return 4;
    for (unsigned c = 0; c < N; c++)
        dma_release(MIG3_DMA_BASE, c);
    return 0;
}

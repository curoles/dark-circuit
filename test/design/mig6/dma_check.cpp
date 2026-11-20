// The DMA of every PE of TbMig6 (chunk 8b, rtl/design/mig6/README.md), checked and timed: each
// PE's DmaSifive (sw/riscv/drivers/dma.h), its registers the region dma, moves data from the
// shared memory into the PE's local memory over the network. Hart 0 writes a pattern into
// the shared memory, a block of BLOCK bytes for each hart (a PE's part of the int8 layer: 4
// rows of weights and the input); a barrier. Then:
//   1. hart 0 alone, the others waiting at a barrier: the first 4, 64 and BLOCK bytes of its
//      block, shared -> local (4 bytes: about one round trip on the network); BLOCK bytes
//      local -> local (the DMA without the network);
//   2. every hart at once, its own block, shared -> local (the shared memory and the
//      network under four PEs).
// Each transfer goes into a zeroed buffer, is checked byte for byte and timed by the cycle
// CSR from run to done (polled: run's fence, the transfer, done's read and fence). Prints
// "dma: hart <h> <what> <n> bytes: <c> cycles". Exit 0 when every byte agrees, 1 at a
// mismatch, 2 when a barrier's wait ends without every hart, 3 when a transfer does not
// end within WAIT clocks.
//
// @author    Igor Lesik
// @copyright 2026 Igor Lesik, MIT License

#include <stdint.h>

#include "mig6/mig6_csr_ops.hpp"
#include "mig6/mig6_pma.hpp"
#include "mig6/mig6_shmem_amo_add_barrier.hpp"
#include "tprintf.h"

extern "C" {
#include "drivers/dma.h"
}

using namespace mig6;

namespace {

constexpr uint32_t  N_HARTS  = 4;               // TbMig6's PEs (Mig6NocPkg::N_PES)
constexpr uint32_t  BLOCK    = 320;             // a PE's part of the layer: 4 x 64 + 64 bytes
constexpr uint32_t  COUNT_AT = 0x00;            // the barriers' counter
constexpr uint32_t  DATA_AT  = 0x100;           // hart h's block at DATA_AT + BLOCK h
constexpr uint32_t  WAIT     = 100000;          // clocks a hart waits for a barrier, a transfer
constexpr uintptr_t DMA      = pma::dma::base;  // the PE's DMA, channel 0
constexpr unsigned  CH       = 0;

static_assert(BLOCK % 4 == 0, "a block is whole words");
static_assert(DATA_AT + N_HARTS * BLOCK <= pma::shared::size, "the blocks fit");

uint8_t buf[BLOCK]       __attribute__((aligned(4)));   // every transfer's destination
uint8_t local_src[BLOCK] __attribute__((aligned(4)));   // the local -> local source

// Byte i of hart h's block.
uint8_t pattern(uint32_t h, uint32_t i)
{
    return static_cast<uint8_t>(7 * i + 31 * h + 1);
}

// One transfer of n bytes into buf (zeroed first), timed from run to done, then checked
// against hart h's block: 0 when every byte agrees, 1 at a mismatch, 3 when it does not end.
int transfer(uint32_t hart, const char* what, uintptr_t src, uint32_t n, uint32_t h)
{
    for (uint32_t i = 0; i < BLOCK; i++)
        buf[i] = 0;
    dma_setup(DMA, CH, src, reinterpret_cast<uintptr_t>(buf), n);
    const uint32_t t = csr::cycle::read();
    dma_run(DMA, CH, 0);
    while (!dma_done(DMA, CH))
        if (csr::cycle::read() - t > WAIT) {
            tprintf("dma: hart %u %s %u bytes: no end, %u left\n", hart, what, n,
                    dma_left(DMA, CH));
            return 3;
        }
    const uint32_t cycles = csr::cycle::read() - t;
    dma_clear(DMA, CH);
    tprintf("dma: hart %u %s %u bytes: %u cycles\n", hart, what, n, cycles);
    for (uint32_t i = 0; i < n; i++)
        if (buf[i] != pattern(h, i)) {
            tprintf("dma: hart %u %s: byte %u is %u, expected %u\n", hart, what, i, buf[i],
                    pattern(h, i));
            return 1;
        }
    return 0;
}

}   // namespace

// extern "C": crt0.S calls main (freestanding, its name would be mangled).
extern "C" int main()
{
    ShmemAmoAddBarrier bar(pma::shared::at<uint32_t, COUNT_AT>(), N_HARTS);
    const uint32_t     hart  = csr::mhartid::read();
    const uintptr_t    mine  = pma::shared::base + DATA_AT + BLOCK * hart;  // my block
    int                r     = 0;

    dma_claim(DMA, CH);
    if (hart == 0)
        for (uint32_t i = 0; i < N_HARTS * BLOCK; i += 4) {
            const uint32_t h = i / BLOCK;
            const uint32_t j = i % BLOCK;
            uint32_t w = 0;
            for (uint32_t b = 0; b < 4; b++)
                w |= static_cast<uint32_t>(pattern(h, j + b)) << (8 * b);
            *pma::shared::at<uint32_t>(DATA_AT + i) = w;
        }
    if (!bar.wait(WAIT))
        return 2;

    if (hart == 0) {
        const uint32_t sizes[] = {4, 64, BLOCK};
        for (uint32_t n : sizes)
            if ((r = transfer(hart, "alone, shared -> local", mine, n, 0)) != 0)
                return r;
        for (uint32_t i = 0; i < BLOCK; i++)
            local_src[i] = pattern(0, i);
        if ((r = transfer(hart, "alone, local -> local", reinterpret_cast<uintptr_t>(local_src),
                          BLOCK, 0)) != 0)
            return r;
    }
    if (!bar.wait(WAIT))
        return 2;

    if ((r = transfer(hart, "all four, shared -> local", mine, BLOCK, hart)) != 0)
        return r;
    dma_release(DMA, CH);
    return 0;
}

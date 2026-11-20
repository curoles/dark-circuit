// LR/SC on a PE's local memory, decided by its exclusive monitor at the local memory's port
// (kb rtl/design/mig6/local_lr_sc), on every PE of TbMig6 at once (each its own memory).
// Between an lr.w and an sc.w of a word, one thing happens, and the SC must say what the
// monitor saw:
//   1. nothing: the SC stores (0);
//   2. the DMA (local -> local) writes the reserved word: the SC fails (1), the DMA's
//      value stays;
//   3. the DMA writes another line: the SC stores;
//   4. the hart's own plain store to the word: the SC fails (the monitor ends the
//      reservation on every write of the line, the writer's own too; the spec allows it);
//   5. an interrupt (the DMA's done) whose handler stores to the word: the SC fails.
// The DMA is polled but in 5. Prints "lrsc: hart <h> case <c>: sc <r>, word <v>" and exits
// with 0 when every SC and word is as expected; 1 when one is not, 3 when a transfer does
// not end within WAIT clocks, 4 when the interrupt does not come.
//
// @author    Igor Lesik
// @copyright 2026 Igor Lesik, MIT License

#include <stdint.h>

#include "mig6/mig6_config.h"
#include "mig6/mig6_csr_ops.hpp"
#include "mig6/mig6_pma.hpp"
#include "tprintf.h"

extern "C" {
#include "drivers/dma.h"
#include "drivers/plic.h"
}

using namespace mig6;

namespace {

constexpr uint32_t  WAIT   = 20000;             // clocks a transfer, the interrupt may take
constexpr uintptr_t DMA    = pma::dma::base;    // the PE's DMA, channel 0
constexpr uintptr_t PLIC   = pma::plic::base;   // the PE's PLIC, context 0
constexpr unsigned  CH     = 0;
constexpr unsigned  SRC    = MIG6_DMA_DONE_SOURCE(CH);
constexpr uint32_t  START  = 0x11111111u;       // the word before each case
constexpr uint32_t  SC_VAL = 0x5c5c5c5cu;       // what the SC stores
constexpr uint32_t  OTHER  = 0xd0d0d0d0u;       // what a writer between them stores

static_assert(pma::local::reservable, "LR/SC on the local memory");

// The reserved word alone in its line (a reservation is a line of the local memory), and
// a word of another line; the DMA's source.
volatile uint32_t word  __attribute__((aligned(16)));
volatile uint32_t other __attribute__((aligned(16)));
uint32_t          src   __attribute__((aligned(16))) = OTHER;
volatile uint32_t irqs;
volatile bool     handler_stores;               // case 5: the handler stores to word

uint32_t lr_w(volatile uint32_t* p)
{
    uint32_t v;
    __asm__ volatile("lr.w %0, (%1)" : "=r"(v) : "r"(p) : "memory");
    return v;
}

uint32_t sc_w(volatile uint32_t* p, uint32_t v)
{
    uint32_t r;
    __asm__ volatile("sc.w %0, %2, (%1)" : "=&r"(r) : "r"(p), "r"(v) : "memory");
    return r;
}

// src -> dst, 4 bytes, by the DMA; ie: its done interrupt; polled when !ie. False when it
// does not end within WAIT clocks.
bool dma_word(volatile uint32_t* dst, bool ie)
{
    dma_setup(DMA, CH, reinterpret_cast<uintptr_t>(&src),
              reinterpret_cast<uintptr_t>(const_cast<uint32_t*>(dst)), 4);
    const uint32_t before = irqs;
    const uint32_t t      = csr::cycle::read();
    dma_run(DMA, CH, ie);
    if (ie) {
        while (irqs == before)
            if (csr::cycle::read() - t > WAIT)
                return false;
        return true;
    }
    while (!dma_done(DMA, CH))
        if (csr::cycle::read() - t > WAIT)
            return false;
    dma_clear(DMA, CH);
    return true;
}

}   // namespace

extern "C" __attribute__((interrupt("machine"))) void handler()
{
    const uint32_t id = plic_claim(PLIC);
    if (id == SRC && dma_done(DMA, CH)) {
        dma_clear(DMA, CH);
        if (handler_stores)
            word = OTHER;
        irqs = irqs + 1;
    }
    plic_complete(PLIC, id);
}

// extern "C": crt0.S calls main (freestanding, its name would be mangled).
extern "C" int main()
{
    const uint32_t hart = csr::mhartid::read();
    // Per case: the SC's result and the word after it.
    struct { uint32_t sc, value; } const want[] = {
        {0, SC_VAL}, {1, OTHER}, {0, SC_VAL}, {1, OTHER}, {1, OTHER}};

    dma_claim(DMA, CH);
    plic_set_priority(PLIC, SRC, 1);
    plic_enable(PLIC, SRC);
    plic_set_threshold(PLIC, 0);
    csr::mtvec::write(static_cast<uint32_t>(reinterpret_cast<uintptr_t>(&handler)));
    csr::mie::set(csr::mie::meie_mask);
    csr::mstatus::set(csr::mstatus::mie_mask);

    for (uint32_t c = 1; c <= 5; c++) {
        word = START;
        (void)lr_w(&word);
        bool ok = true;
        switch (c) {
        case 2: ok = dma_word(&word, false);                break;
        case 3: ok = dma_word(&other, false);               break;
        case 4: word = OTHER;                               break;
        case 5: handler_stores = true;
                ok = dma_word(&other, true);
                handler_stores = false;                     break;
        default:                                            break;
        }
        if (!ok)
            return c == 5 ? 4 : 3;
        const uint32_t r = sc_w(&word, SC_VAL);
        const uint32_t v = word;
        tprintf("lrsc: hart %u case %u: sc %u, word %08x\n", hart, c, r, v);
        if (r != want[c - 1].sc || v != want[c - 1].value)
            return 1;
    }
    csr::mstatus::clear(csr::mstatus::mie_mask);
    dma_release(DMA, CH);
    return 0;
}

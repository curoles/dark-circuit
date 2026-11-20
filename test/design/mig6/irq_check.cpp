// The PLIC of every PE of TbMig6 (chunk 8b, rtl/design/mig6/README.md) with its DMA's done as
// the interrupt (sw/riscv/drivers/plic.h, dma.h): each hart copies BLOCK bytes local ->
// local (no network: the interrupt's own cycles) three ways, each timed from run by the cycle
// CSR, every byte checked:
//   1. polled: dma_done in a loop, as dma_check (the reference);
//   2. interrupt, spinning: main spins on a counter the handler bumps;
//   3. interrupt, WFI: main waits in WFI with MIE off (a pending interrupt wakes WFI), then
//      sets MIE to take it, so an interrupt that comes before WFI is not lost.
// The handler (machine mode, mtvec direct): the cycle at its first statement, claim, the
// DMA's done checked and cleared (dma_clear: the write, then the read-back, so the level
// has dropped), complete. Prints "irq: hart <h> <way>: run -> done <c> cycles" for 1, and
// "... run -> handler <e>, run -> main <c> cycles" for 2 and 3. Exit 0 when every byte and
// every interrupt is right, 1 at a wrong byte, 3 when a transfer does not end within WAIT
// clocks, 4 at an interrupt other than the DMA's done or a missing one.
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

constexpr uint32_t  BLOCK = 64;                 // bytes a transfer
constexpr uint32_t  WAIT  = 20000;              // clocks a transfer may take
constexpr uintptr_t DMA   = pma::dma::base;     // the PE's DMA, channel 0
constexpr uintptr_t PLIC  = pma::plic::base;    // the PE's PLIC, context 0
constexpr unsigned  CH    = 0;
constexpr unsigned  SRC   = MIG6_DMA_DONE_SOURCE(CH);

uint8_t src[BLOCK] __attribute__((aligned(4)));
uint8_t dst[BLOCK] __attribute__((aligned(4)));

volatile uint32_t irqs;         // the DMA's done interrupts handled
volatile uint32_t wrong;        // claims of another source, or without done
volatile uint32_t entry_at;     // the cycle at the handler's first statement

uint8_t pattern(uint32_t hart, uint32_t way, uint32_t i)
{
    return static_cast<uint8_t>(5 * i + 41 * hart + 17 * way + 3);
}

}   // namespace

extern "C" __attribute__((interrupt("machine"))) void handler()
{
    entry_at = csr::cycle::read();
    const uint32_t id = plic_claim(PLIC);
    if (id == SRC && dma_done(DMA, CH)) {
        irqs = irqs + 1;
        dma_clear(DMA, CH);         // the write, then the read-back: the level has dropped
    } else {
        wrong = wrong + 1;
    }
    plic_complete(PLIC, id);
}

namespace {

// Way 0 polled, 1 by interrupt while spinning, 2 by interrupt in WFI: src -> dst, timed and
// checked. 0 when right, else the exit code.
int transfer(uint32_t hart, uint32_t way)
{
    static const char* const names[] = {"polled", "interrupt, spinning", "interrupt, WFI"};
    for (uint32_t i = 0; i < BLOCK; i++) {
        src[i] = pattern(hart, way, i);
        dst[i] = 0;
    }
    dma_setup(DMA, CH, reinterpret_cast<uintptr_t>(src), reinterpret_cast<uintptr_t>(dst),
              BLOCK);
    const uint32_t before = irqs;
    if (way == 2)
        csr::mstatus::clear(csr::mstatus::mie_mask);
    const uint32_t t = csr::cycle::read();
    dma_run(DMA, CH, way != 0);
    if (way == 0) {
        while (!dma_done(DMA, CH))
            if (csr::cycle::read() - t > WAIT)
                return 3;
    } else {
        while (irqs == before) {
            if (csr::cycle::read() - t > WAIT)
                return 3;
            if (way == 2) {
                __asm__ volatile("wfi");
                csr::mstatus::set(csr::mstatus::mie_mask);      // the interrupt is taken here
                csr::mstatus::clear(csr::mstatus::mie_mask);
            }
        }
    }
    const uint32_t c = csr::cycle::read() - t;
    if (way == 0) {
        dma_clear(DMA, CH);
        tprintf("irq: hart %u %s: run -> done %u cycles\n", hart, names[way], c);
    } else {
        csr::mstatus::set(csr::mstatus::mie_mask);
        tprintf("irq: hart %u %s: run -> handler %u, run -> main %u cycles\n", hart,
                names[way], entry_at - t, c);
        if (irqs != before + 1 || wrong != 0)
            return 4;
    }
    for (uint32_t i = 0; i < BLOCK; i++)
        if (dst[i] != pattern(hart, way, i)) {
            tprintf("irq: hart %u %s: byte %u is %u, expected %u\n", hart, names[way], i,
                    dst[i], pattern(hart, way, i));
            return 1;
        }
    return 0;
}

}   // namespace

// extern "C": crt0.S calls main (freestanding, its name would be mangled).
extern "C" int main()
{
    const uint32_t hart = csr::mhartid::read();

    dma_claim(DMA, CH);
    plic_set_priority(PLIC, SRC, 1);
    plic_enable(PLIC, SRC);
    plic_set_threshold(PLIC, 0);
    csr::mtvec::write(static_cast<uint32_t>(reinterpret_cast<uintptr_t>(&handler)));
    csr::mie::set(csr::mie::meie_mask);
    csr::mstatus::set(csr::mstatus::mie_mask);

    for (uint32_t way = 0; way < 3; way++)
        if (const int r = transfer(hart, way); r != 0)
            return r;
    csr::mstatus::clear(csr::mstatus::mie_mask);
    dma_release(DMA, CH);
    return 0;
}

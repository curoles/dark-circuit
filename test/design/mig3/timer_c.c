/* Test of the drivers sw/riscv/drivers/timer.h and plic.h on Mig3 (TbMig3, judged by the exit
 * status): the Timer's interrupt through the PLIC, taken by a C handler (GCC's interrupt
 * attribute: it saves what it uses and returns with MRET).
 *
 * The program sets an alarm PERIOD ticks ahead, enables the Timer's source at the PLIC, MEIE
 * and MIE, and waits for N interrupts. The handler claims; for the Timer's ID with the alarm
 * due it counts and re-arms (timer_rearm: the write, then the read-back), the last time it
 * switches the alarm off (timer_off); it completes after. A wrong ID or an entry with the
 * alarm not due (spurious: tolerated, completed and ignored) is counted. Then a wait of
 * 3 * PERIOD ticks: no interrupt without an alarm. Exit 0 when N interrupts came, each with
 * the Timer's ID and the alarm due, and no spurious one, else 1. This test checks that the
 * drivers work, not that their read-back is needed: the compiler puts an instruction between
 * the write of mtimecmp and the complete, which here already gives the line the clock it
 * needs (without the read-backs this test passes too). timer.S shows the need: its stores
 * back to back took a fourth interrupt without the read-back.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
#include <stdint.h>

#include "mig3_config.h"
#include "drivers/plic.h"
#include "drivers/timer.h"

#define PERIOD  500u    // ticks between the alarms (clocks on Mig3)
#define N       3u      // interrupts

static volatile unsigned count;     // interrupts of the Timer with the alarm due
static volatile unsigned spurious;  // ... with the alarm not due
static volatile unsigned wrong_id;  // claims of another ID

__attribute__((interrupt("machine"))) static void handler(void)
{
    uint32_t id = plic_claim(MIG3_PLIC_BASE);
    if (id != MIG3_TIMER_SOURCE) {
        wrong_id++;
    } else if (!timer_due(MIG3_TIMER_BASE, 0)) {
        spurious++;                                 // tolerated: complete and return
    } else if (++count < N) {
        timer_rearm(MIG3_TIMER_BASE, 0, PERIOD);    // the write, then the read-back
    } else {
        timer_off(MIG3_TIMER_BASE, 0);
    }
    plic_complete(MIG3_PLIC_BASE, id);
}

int main(void)
{
    plic_set_priority(MIG3_PLIC_BASE, MIG3_TIMER_SOURCE, 1);
    plic_enable(MIG3_PLIC_BASE, MIG3_TIMER_SOURCE);
    __asm__ volatile("csrw mtvec, %0" : : "r"(handler));    // direct mode
    __asm__ volatile("csrs mie, %0" : : "r"(1u << 11));     // MEIE
    timer_set(MIG3_TIMER_BASE, 0, timer_mtime(MIG3_TIMER_BASE) + PERIOD);
    __asm__ volatile("csrsi mstatus, 8");                   // MIE
    while (count < N) {
    }
    uint64_t end = timer_mtime(MIG3_TIMER_BASE) + 3u * PERIOD;
    while (timer_mtime(MIG3_TIMER_BASE) < end) {
    }
    return (count == N && spurious == 0 && wrong_id == 0) ? 0 : 1;
}

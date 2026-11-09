/* Test of the UART of Mig3 and its driver sw/riscv/drivers/uart.h (TbMig3: the console's
 * text must match the test's OUTPUT, and the exit status 0).
 *
 * The program sets the boot rate (MIG3_UART_DIV_RST, the testbench's line), prints a line
 * polling (uart_puts: each byte after reading full), then sends a second line, longer than
 * the FIFO, by the transmit watermark's interrupt: txcnt 4, ie.txwm, the UART's source at the
 * PLIC. The handler claims; for the UART's ID with ip.txwm it refills the FIFO until full or
 * the line ends, then reads the UART back (uart_sync), or at the end switches the interrupt
 * off (uart_set_ie: the write, then the read-back); it completes after. A wrong ID or an
 * entry without txwm (spurious) is counted. Exit 0 when the line went out in more than one
 * interrupt, each with the UART's ID and txwm, else 1. The testbench prints the characters
 * as they come and waits for the line to go idle after the exit.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
#include <stdint.h>

#include "mig3_config.h"
#include "drivers/plic.h"
#include "drivers/uart.h"

static const char line[] = "Interrupt-driven: the transmit watermark refills the FIFO.\n";

static volatile unsigned pos;       // the next byte of line to send
static volatile unsigned count;     // interrupts of the UART with txwm
static volatile unsigned spurious;  // ... without txwm
static volatile unsigned wrong_id;  // claims of another ID

__attribute__((interrupt("machine"))) static void handler(void)
{
    uint32_t id = plic_claim(MIG3_PLIC_BASE);
    if (id != MIG3_UART_SOURCE) {
        wrong_id++;
    } else if (!(*uart_reg(MIG3_UART_BASE, UART_IP) & UART_TXWM)) {
        spurious++;
    } else {
        count++;
        while (line[pos] && uart_putc_try(MIG3_UART_BASE, line[pos]))
            pos++;
        if (line[pos])
            uart_sync(MIG3_UART_BASE);              // the FIFO full: read back
        else
            uart_set_ie(MIG3_UART_BASE, 0);         // the end: off, read back
    }
    plic_complete(MIG3_PLIC_BASE, id);
}

int main(void)
{
    uart_init(MIG3_UART_BASE, MIG3_UART_DIV_RST);
    uart_puts(MIG3_UART_BASE, "Hello from Mig3 over the UART\n");

    plic_set_priority(MIG3_PLIC_BASE, MIG3_UART_SOURCE, 1);
    plic_enable(MIG3_PLIC_BASE, MIG3_UART_SOURCE);
    __asm__ volatile("csrw mtvec, %0" : : "r"(handler));    // direct mode
    __asm__ volatile("csrs mie, %0" : : "r"(1u << 11));     // MEIE
    uart_set_watermarks(MIG3_UART_BASE, 4, 0);
    uart_set_ie(MIG3_UART_BASE, UART_TXWM);
    __asm__ volatile("csrsi mstatus, 8");                   // MIE
    while (line[pos]) {
    }
    return (count > 1 && spurious == 0 && wrong_id == 0) ? 0 : 1;
}

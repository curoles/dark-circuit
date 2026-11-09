/* UART driver: the library's UartSifive (rtl/lib/io/uart/uart_sifive), SiFive's UART: its
 * register map, so code written for a SiFive UART works too.
 *
 * base is the UART's address, from a design's config header (MIG3_UART_BASE). The offsets and
 * bits are as in UartSifivePkg (rtl/lib/io/uart/uart_sifive/uart_sifive_pkg.sv).
 *
 * How the hardware works
 *
 * Frames of 8 data bits, no parity, 1 stop bit (2 with UART_NSTOP), at f / (div + 1) bits a
 * second; a write of div starts the new rate at once. Each direction has a FIFO of 8 bytes.
 *  - Transmit: a write of txdata puts its byte into the transmit FIFO; when the FIFO is full
 *    the byte is dropped, so read txdata first: UART_FULL says there is no room (uart_putc).
 *    With UART_TXEN the bytes go out one after the other. There is no "all sent" flag: an
 *    empty FIFO (ip's UART_TXWM with a transmit watermark of 1) still has its last byte on
 *    the line.
 *  - Receive: with UART_RXEN every byte received goes into the receive FIFO, dropped when it
 *    is full (no overrun flag, no framing or parity error flags). A read of rxdata takes the
 *    oldest byte out: every read of rxdata pops, so read it once and look at UART_EMPTY in
 *    that same value (uart_getc). Never read rxdata to "check" it.
 *  - Interrupt: ip's UART_TXWM is 1 while the transmit FIFO has fewer than txcnt bytes (room:
 *    refill it), UART_RXWM while the receive FIFO has more than rxcnt (drain it); the UART's
 *    interrupt is any of ip & ie, a level (Mig3: PLIC source MIG3_UART_SOURCE).
 *
 * The rule when its interrupt goes through a PLIC
 *
 * A PLIC source is level-triggered: if the UART's line is still 1 when the handler completes,
 * the interrupt comes again. The line drops one clock after the access that ends the
 * condition. After a read of rxdata (the pop) that is no worry: the read's answer comes after
 * the drop. After a write (txdata bytes that fill the FIFO up to the watermark, or ie
 * cleared) the complete can reach the PLIC in the very clock the line drops: read the UART
 * back before completing (uart_sync, called by uart_set_ie; read ie, never rxdata), as for the
 * Timer (timer.h has the clock-by-clock reason).
 *
 *   void handler(void)                                 // the interrupt of the PLIC
 *   {
 *       uint32_t id = plic_claim(PLIC);
 *       if (id == UART_SOURCE) {
 *           while (more && uart_putc_try(UART, next()))
 *               ;                                      // refill
 *           if (!more)
 *               uart_set_ie(UART, 0);                  // no more: off, read back
 *           else
 *               uart_sync(UART);                       // refilled: read back
 *       }
 *       plic_complete(PLIC, id);                       // the line has dropped
 *   }
 *
 * Why: kb rtl/design/mig3/uart, kb rtl/lib/io/uart/uart_sifive/design.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
#pragma once

#include <stdint.h>

#define UART_TXDATA     0x00u       // [7:0] a byte to send; [31] UART_FULL (read)
#define UART_RXDATA     0x04u       // [7:0] the byte received (a read pops); [31] UART_EMPTY
#define UART_TXCTRL     0x08u       // UART_TXEN, UART_NSTOP, UART_CNT(txcnt)
#define UART_RXCTRL     0x0cu       // UART_RXEN, UART_CNT(rxcnt)
#define UART_IE         0x10u       // UART_TXWM, UART_RXWM: interrupt enables
#define UART_IP         0x14u       // UART_TXWM, UART_RXWM: pending (read only)
#define UART_DIV        0x18u       // the rate: f / (div + 1)

#define UART_FULL       (1u << 31)  // txdata: no room for a byte
#define UART_EMPTY      (1u << 31)  // rxdata: no byte (the data field is not one)
#define UART_TXEN       (1u << 0)
#define UART_NSTOP      (1u << 1)   // two stop bits
#define UART_RXEN       (1u << 0)
#define UART_CNT(n)     ((uint32_t)(n) << 16)   // a watermark, 0 to 7
#define UART_TXWM       (1u << 0)
#define UART_RXWM       (1u << 1)

static inline volatile uint32_t *uart_reg(uintptr_t base, uintptr_t offset)
{
    return (volatile uint32_t *)(base + offset);
}

// The rate, transmit and receive on, the watermarks 0 (txwm never, rxwm for every byte).
static inline void uart_init(uintptr_t base, uint32_t div)
{
    *uart_reg(base, UART_DIV)    = div;
    *uart_reg(base, UART_TXCTRL) = UART_TXEN;
    *uart_reg(base, UART_RXCTRL) = UART_RXEN;
}

// The watermarks (transmit and receive stay on).
static inline void uart_set_watermarks(uintptr_t base, unsigned txcnt, unsigned rxcnt)
{
    *uart_reg(base, UART_TXCTRL) = UART_TXEN | UART_CNT(txcnt);
    *uart_reg(base, UART_RXCTRL) = UART_RXEN | UART_CNT(rxcnt);
}

// A read of the UART that has no effect: after it returns, every write before it has acted
// (the interrupt line is where those writes put it). Not rxdata: its read pops.
static inline void uart_sync(uintptr_t base)
{
    (void)*uart_reg(base, UART_IE);
}

// The interrupt enables (UART_TXWM, UART_RXWM), then the read-back (see above).
static inline void uart_set_ie(uintptr_t base, uint32_t ie)
{
    *uart_reg(base, UART_IE) = ie;
    uart_sync(base);
}

// Put c into the transmit FIFO if there is room: 1, else 0 (nothing written).
static inline int uart_putc_try(uintptr_t base, char c)
{
    if (*uart_reg(base, UART_TXDATA) & UART_FULL)
        return 0;
    *uart_reg(base, UART_TXDATA) = (uint8_t)c;
    return 1;
}

// Put c into the transmit FIFO, waiting for room.
static inline void uart_putc(uintptr_t base, char c)
{
    while (!uart_putc_try(base, c)) {
    }
}

static inline void uart_puts(uintptr_t base, const char *s)
{
    while (*s)
        uart_putc(base, *s++);
}

// The oldest byte received, taken out of the receive FIFO, or -1 when it is empty: one read.
static inline int uart_getc(uintptr_t base)
{
    uint32_t v = *uart_reg(base, UART_RXDATA);
    return (v & UART_EMPTY) ? -1 : (int)(v & 0xffu);
}

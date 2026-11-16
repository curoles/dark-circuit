/* THIS FILE IS GENERATED, DO NOT EDIT MANUALLY!
 * Generated from rtl/design/mig6/cfg/mig6_config.yaml and mig6_config.h.j2 by tools/config_gen.py
 *
 * Configuration of Mig6 for programs, also usable in assembly (.S).
 */
#pragma once

/* PC after reset. */
#define MIG6_RST_ADDR 0x00000000u

/* The memory, code and data: 1 << MIG6_MEM_ADDR_WIDTH = MIG6_MEM_SIZE bytes. */
#define MIG6_MEM_ADDR_WIDTH 16
#define MIG6_MEM_SIZE 65536u

/* I/O region, uncached: MIG6_IO_BASE, 1 << MIG6_IO_ADDR_WIDTH bytes. */
#define MIG6_IO_BASE 0x0c000000
#define MIG6_IO_ADDR_WIDTH 26

/* PLIC (riscv-plic-spec register map), context 0 = the hart's M-mode: sources 1 to
 * MIG6_PLIC_SOURCES, priorities 0 to MIG6_PLIC_PRIO_MAX. The offsets are the spec's, as in
 * PlicPkg (rtl/lib/block/plic/plic_pkg.sv). */
#define MIG6_PLIC_BASE 0x0c000000
#define MIG6_PLIC_SOURCES 16
#define MIG6_PLIC_PRIO_MAX 7
#define MIG6_PLIC_PRIORITY(k)  (MIG6_PLIC_BASE + 4 * (k))
#define MIG6_PLIC_PENDING      (MIG6_PLIC_BASE + 0x1000)
#define MIG6_PLIC_ENABLE       (MIG6_PLIC_BASE + 0x2000)
#define MIG6_PLIC_THRESHOLD    (MIG6_PLIC_BASE + 0x200000)
#define MIG6_PLIC_CLAIM        (MIG6_PLIC_BASE + 0x200004)

/* Timer (the CLINT's timer: mtime, mtimecmp of hart 0), its interrupt PLIC source
 * MIG6_TIMER_SOURCE. 64-bit registers as two words, the low word first; the offsets are
 * the CLINT's, as in TimerPkg (rtl/lib/block/timer/timer_pkg.sv). */
#define MIG6_TIMER_BASE 0x0c400000
#define MIG6_TIMER_SOURCE 2
#define MIG6_TIMER_MTIMECMP    (MIG6_TIMER_BASE + 0x4000)
#define MIG6_TIMER_MTIME       (MIG6_TIMER_BASE + 0xbff8)

/* UART (SiFive's: txdata, rxdata, txctrl, rxctrl, ie, ip, div; sw/riscv/drivers/uart.h), its
 * interrupt PLIC source MIG6_UART_SOURCE. div is MIG6_UART_DIV_RST after reset: the boot
 * rate, f / (MIG6_UART_DIV_RST + 1), the rate of the testbench's line. */
#define MIG6_UART_BASE 0x0c410000
#define MIG6_UART_SOURCE 3
#define MIG6_UART_DIV_RST 15

/* DMA (SiFive's PDMA: a channel's registers every 0x1000; sw/riscv/drivers/dma.h), a second
 * agent on the memory. Channel c's interrupts are PLIC sources MIG6_DMA_SOURCE + 2c (done)
 * and MIG6_DMA_SOURCE + 2c + 1 (error). */
#define MIG6_DMA_BASE 0x0c420000
#define MIG6_DMA_CHANNELS 4
#define MIG6_DMA_SOURCE 4
#define MIG6_DMA_DONE_SOURCE(c)   (MIG6_DMA_SOURCE + 2 * (c))
#define MIG6_DMA_ERROR_SOURCE(c)  (MIG6_DMA_SOURCE + 2 * (c) + 1)

/* Cache-block operations (Zicbom: cbo.clean, cbo.flush, cbo.inval; sw/riscv/drivers/cbo.h)
 * act on the block of MIG6_CBO_BLOCK_SIZE bytes that holds the address: a line of the data
 * cache. */
#define MIG6_CBO_BLOCK_SIZE 8u

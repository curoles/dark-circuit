/* THIS FILE IS GENERATED, DO NOT EDIT MANUALLY!
 * Generated from rtl/design/mig3/cfg/mig3_config.yaml and mig3_config.h.j2 by tools/config_gen.py
 *
 * Configuration of Mig3 for programs, also usable in assembly (.S).
 */
#pragma once

/* PC after reset. */
#define MIG3_RST_ADDR 0x00000000u

/* The memory, code and data: 1 << MIG3_MEM_ADDR_WIDTH = MIG3_MEM_SIZE bytes. */
#define MIG3_MEM_ADDR_WIDTH 16
#define MIG3_MEM_SIZE 65536u

/* I/O region, uncached: MIG3_IO_BASE, 1 << MIG3_IO_ADDR_WIDTH bytes. */
#define MIG3_IO_BASE 0x0c000000
#define MIG3_IO_ADDR_WIDTH 26

/* PLIC (riscv-plic-spec register map), context 0 = the hart's M-mode: sources 1 to
 * MIG3_PLIC_SOURCES, priorities 0 to MIG3_PLIC_PRIO_MAX. The offsets are the spec's, as in
 * PlicPkg (rtl/lib/block/plic/plic_pkg.sv). */
#define MIG3_PLIC_BASE 0x0c000000
#define MIG3_PLIC_SOURCES 8
#define MIG3_PLIC_PRIO_MAX 7
#define MIG3_PLIC_PRIORITY(k)  (MIG3_PLIC_BASE + 4 * (k))
#define MIG3_PLIC_PENDING      (MIG3_PLIC_BASE + 0x1000)
#define MIG3_PLIC_ENABLE       (MIG3_PLIC_BASE + 0x2000)
#define MIG3_PLIC_THRESHOLD    (MIG3_PLIC_BASE + 0x200000)
#define MIG3_PLIC_CLAIM        (MIG3_PLIC_BASE + 0x200004)

/* Timer (the CLINT's timer: mtime, mtimecmp of hart 0), its interrupt PLIC source
 * MIG3_TIMER_SOURCE. 64-bit registers as two words, the low word first; the offsets are
 * the CLINT's, as in TimerPkg (rtl/lib/block/timer/timer_pkg.sv). */
#define MIG3_TIMER_BASE 0x0c400000
#define MIG3_TIMER_SOURCE 2
#define MIG3_TIMER_MTIMECMP    (MIG3_TIMER_BASE + 0x4000)
#define MIG3_TIMER_MTIME       (MIG3_TIMER_BASE + 0xbff8)

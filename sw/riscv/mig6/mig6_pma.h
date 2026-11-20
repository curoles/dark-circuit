/* THIS FILE IS GENERATED, DO NOT EDIT MANUALLY!
 * Generated from rtl/design/mig6/cfg/mig6_pma.yaml and mig6_pma.h.j2 by tools/pma_gen.py
 *
 * Mig6's memory map for programs and tests, as rtl/design/mig6/cfg/mig6_pma.yaml describes
 * it (PMA-style: physical memory attributes); plain numbers, also usable in assembly (.S).
 * Per region: MIG6_PMA_<NAME>_BASE, _SIZE, _ADDR_WIDTH (the low address bits inside it), and
 * its attributes, 1 or 0: _CACHEABLE, _IO, _ATOMICS, _RESERVABLE.
 */
#pragma once

/* local: the PE's local memory, code and data, private to its core (target: local) */
#define MIG6_PMA_LOCAL_BASE 0x00000000
#define MIG6_PMA_LOCAL_SIZE 0x00010000
#define MIG6_PMA_LOCAL_ADDR_WIDTH 16
#define MIG6_PMA_LOCAL_CACHEABLE 0
#define MIG6_PMA_LOCAL_IO 0
#define MIG6_PMA_LOCAL_ATOMICS 0
#define MIG6_PMA_LOCAL_RESERVABLE 1

/* plic: the PE's PLIC (rtl/lib/block/plic, sw/riscv/drivers/plic.h), one context: meip (target: devices) */
#define MIG6_PMA_PLIC_BASE 0x0c000000
#define MIG6_PMA_PLIC_SIZE 0x00400000
#define MIG6_PMA_PLIC_ADDR_WIDTH 22
#define MIG6_PMA_PLIC_CACHEABLE 0
#define MIG6_PMA_PLIC_IO 1
#define MIG6_PMA_PLIC_ATOMICS 0
#define MIG6_PMA_PLIC_RESERVABLE 0

/* dma: the PE's DMA's registers (DmaSifive: SiFive's PDMA map, sw/riscv/drivers/dma.h) (target: devices) */
#define MIG6_PMA_DMA_BASE 0x0c420000
#define MIG6_PMA_DMA_SIZE 0x00001000
#define MIG6_PMA_DMA_ADDR_WIDTH 12
#define MIG6_PMA_DMA_CACHEABLE 0
#define MIG6_PMA_DMA_IO 1
#define MIG6_PMA_DMA_ATOMICS 0
#define MIG6_PMA_DMA_RESERVABLE 0

/* shared: the shared memory at the mesh's edge, one copy that all PEs share (target: net) */
#define MIG6_PMA_SHARED_BASE 0x80000000
#define MIG6_PMA_SHARED_SIZE 0x00100000
#define MIG6_PMA_SHARED_ADDR_WIDTH 20
#define MIG6_PMA_SHARED_CACHEABLE 0
#define MIG6_PMA_SHARED_IO 0
#define MIG6_PMA_SHARED_ATOMICS 1
#define MIG6_PMA_SHARED_RESERVABLE 1

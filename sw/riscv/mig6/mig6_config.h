/* THIS FILE IS GENERATED, DO NOT EDIT MANUALLY!
 * Generated from rtl/design/mig6/cfg/mig6_config.yaml and mig6_config.h.j2 by tools/config_gen.py
 *
 * Configuration of Mig6 for programs, also usable in assembly (.S). The memory map is
 * mig6_pma.h's (rtl/design/mig6/cfg/mig6_pma.yaml).
 */
#pragma once

/* PC after reset. */
#define MIG6_RST_ADDR 0x00000000u

/* Cache-block operations (Zicbom: cbo.clean, cbo.flush, cbo.inval; sw/riscv/drivers/cbo.h)
 * act on the block of MIG6_CBO_BLOCK_SIZE bytes that holds the address: a line of the data
 * cache. */
#define MIG6_CBO_BLOCK_SIZE 8u

/* Each PE's PLIC (sw/riscv/drivers/plic.h, its base mig6_pma.h's MIG6_PMA_PLIC_BASE): the
 * sources of its DMA's channel ch (sw/riscv/drivers/dma.h): done and error. */
#define MIG6_PLIC_PRIO_WIDTH 2
#define MIG6_DMA_DONE_SOURCE(ch)  (1u + 2u * (ch))
#define MIG6_DMA_ERROR_SOURCE(ch) (1u + 2u * (ch) + 1u)

/* Each PE's DMA keeps up to MIG6_DMA_DEPTH transactions (beats of a word) in flight: a
 * transfer whose destination starts after its source by less than that many beats is
 * undefined, and a stop drains up to that many (sw/riscv/drivers/dma.h). */
#define MIG6_DMA_DEPTH 8u

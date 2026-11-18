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

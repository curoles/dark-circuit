/* THIS FILE IS GENERATED, DO NOT EDIT MANUALLY!
 * Generated from rtl/design/mig2/cfg/mig2_config.yaml and mig2_config.h.j2 by tools/config_gen.py
 *
 * Configuration of Mig2 for programs, also usable in assembly (.S).
 */
#pragma once

/* PC after reset. */
#define MIG2_RST_ADDR 0x00000000u

/* imem and dmem: 1 << MIG2_MEM_ADDR_WIDTH = MIG2_MEM_SIZE bytes each. */
#define MIG2_MEM_ADDR_WIDTH 16
#define MIG2_MEM_SIZE 65536u

/* THIS FILE IS GENERATED, DO NOT EDIT MANUALLY!
 * Generated from rtl/design/mig1/cfg/mig1_config.yaml and mig1_config.h.j2 by tools/config_gen.py
 *
 * Configuration of Mig1 for programs, also usable in assembly (.S).
 */
#pragma once

/* PC after reset. */
#define MIG1_RST_ADDR 0x00000000u

/* imem and dmem: 1 << MIG1_MEM_ADDR_WIDTH = MIG1_MEM_SIZE bytes each. */
#define MIG1_MEM_ADDR_WIDTH 16
#define MIG1_MEM_SIZE 65536u

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

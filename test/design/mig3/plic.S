/* Program for TbMig3 with +irq_random +irq_max_gap=1000 +expect_regs: the PLIC of Mig3Cpu
 * from software, polled with MIE = 0 (no handler).
 *
 * The testbench's device (TbMig3Irq) is source 1; it raises its line max_gap clocks after
 * reset, later after random gaps, and drops it when the program stores to irq_claim.
 *  1. Registers, before the device's first request: a write of all ones reads back the bits
 *     a register has (priority 1 and the threshold: MIG3_PLIC_PRIO_MAX; the enables of
 *     sources 1 to MIG3_PLIC_SOURCES, bit 0 of ID 0 reads 0); priority 0 and a pending word
 *     no source has read 0; a claim with nothing pending gets 0.
 *  2. Source 1 at priority 1, threshold 1: pending, but no meip (mip.MEIP 0: the priority is
 *     not above the threshold); the claim is not gated by the threshold (1), and a claim
 *     right after it gets 0: a claim acts once, a no-cache read of the I/O region reaches
 *     the PLIC every time (a cached one would hit). The device acknowledged, completed.
 *  3. Threshold 0: the next request raises meip; the claim gets 1; acknowledged, completed.
 */
#include "mig3_config.h"

    .macro EXPECT_REG r, value
    .word \r, \value
    .endm

    .section .text.start, "ax"
    .globl _start
_start:
    li    t2, -1
    # 1. Registers.
    li    t0, MIG3_PLIC_PRIORITY(1)
    sw    t2, 0(t0)
    lw    s1, 0(t0)                 # MIG3_PLIC_PRIO_MAX
    li    t0, MIG3_PLIC_PRIORITY(0)
    sw    t2, 0(t0)
    lw    s2, 0(t0)                 # source 0: reserved, 0
    li    t0, MIG3_PLIC_ENABLE
    sw    t2, 0(t0)
    lw    s3, 0(t0)                 # sources 1 to MIG3_PLIC_SOURCES, not ID 0
    li    t0, MIG3_PLIC_THRESHOLD
    sw    t2, 0(t0)
    lw    s4, 0(t0)                 # MIG3_PLIC_PRIO_MAX
    li    t0, MIG3_PLIC_PENDING + 4
    lw    s5, 0(t0)                 # no source has a second word: 0
    li    t0, MIG3_PLIC_CLAIM
    lw    s6, 0(t0)                 # nothing pending: 0

    # 2. Priority 1, threshold 1: no meip, the claim not gated, a second claim 0.
    li    t0, MIG3_PLIC_PRIORITY(1)
    li    t1, 1
    sw    t1, 0(t0)
    li    t0, MIG3_PLIC_ENABLE
    li    t1, 2
    sw    t1, 0(t0)
    li    t0, MIG3_PLIC_THRESHOLD
    li    t1, 1
    sw    t1, 0(t0)
    li    t0, MIG3_PLIC_PENDING
1:  lw    t1, 0(t0)
    andi  t1, t1, 2
    beqz  t1, 1b                    # wait until source 1 is pending
    csrr  t1, mip
    srli  t1, t1, 11
    andi  s7, t1, 1                 # MEIP: 0
    li    t0, MIG3_PLIC_CLAIM
    lw    s8, 0(t0)                 # 1
    lw    s9, 0(t0)                 # right after: 0
    la    t1, irq_claim
    sw    zero, 0(t1)               # the device drops its line
    sw    s8, 0(t0)                 # complete

    # 3. Threshold 0: meip.
    li    t1, MIG3_PLIC_THRESHOLD
    sw    zero, 0(t1)
2:  csrr  t1, mip
    srli  t1, t1, 11
    andi  t1, t1, 1
    beqz  t1, 2b                    # wait for MEIP
    lw    s10, 0(t0)                # 1
    la    t1, irq_claim
    sw    zero, 0(t1)
    sw    s10, 0(t0)                # complete
    ebreak

    .word (expect_end - expect) / 8
expect:
    EXPECT_REG 9,  MIG3_PLIC_PRIO_MAX                   # s1
    EXPECT_REG 18, 0                                    # s2
    EXPECT_REG 19, (1 << (MIG3_PLIC_SOURCES + 1)) - 2   # s3
    EXPECT_REG 20, MIG3_PLIC_PRIO_MAX                   # s4
    EXPECT_REG 21, 0                                    # s5
    EXPECT_REG 22, 0                                    # s6
    EXPECT_REG 23, 0                                    # s7
    EXPECT_REG 24, 1                                    # s8
    EXPECT_REG 25, 0                                    # s9
    EXPECT_REG 26, 1                                    # s10
expect_end:

    .data
    .balign 4
irq_claim:
    .word 0

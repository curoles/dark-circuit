/* Program for TbMig3 with +expect_regs: the vxsat CSR of the P extension (packed SIMD), the
 * saturation flag: bit 0, the other bits read 0.
 *
 * - After reset vxsat reads 0.
 * - csrwi of 1 sets it; csrsi and csrci of other bits change nothing but bit 0; csrrw of all
 *   ones returns the old value and leaves 1; csrci of 1 clears it.
 * The saturating P instructions that set it: pk_sat.S.
 * After the halting EBREAK: number of expected registers, then pairs register, value.
 */
    .macro EXPECT_REG r, value
    .word \r, \value
    .endm

    .section .text.start, "ax"
    .globl _start
_start:
    csrr     x1, vxsat              # 0 after reset
    csrwi    vxsat, 1
    csrr     x2, vxsat              # 1
    csrci    vxsat, 0x1e            # bits 4..1: nothing changes
    csrr     x3, vxsat              # 1
    csrwi    vxsat, 0
    csrsi    vxsat, 0x1e            # bits 4..1 only: still 0
    csrr     x4, vxsat              # 0
    li       x5, -1
    csrrw    x6, vxsat, x5          # x6 = 0, vxsat = 1 (bit 0 of all ones)
    csrr     x7, vxsat              # 1
    csrrci   x8, vxsat, 1           # x8 = 1, vxsat = 0
    csrr     x9, vxsat              # 0
    ebreak

    .word (expect_end - expect) / 8
expect:
    EXPECT_REG 1, 0
    EXPECT_REG 2, 1
    EXPECT_REG 3, 1
    EXPECT_REG 4, 0
    EXPECT_REG 6, 0
    EXPECT_REG 7, 1
    EXPECT_REG 8, 1
    EXPECT_REG 9, 0
expect_end:

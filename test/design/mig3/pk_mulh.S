/* Program for TbMig3 with +expect_regs: Mig3's packed high halves (P extension, draft;
 * assembled with clang's experimental P): PMULH.H, PMULHU.H, PMULHSU.H, the rounded PMULHR.H,
 * PMULHRU.H, PMULHRSU.H (2^15 added first), the Q15 PMULQ.H and rounded PMULQR.H (bits 30..15,
 * 2^14 added first for QR; 0x8000 * 0x8000 saturates to 0x7fff and sets vxsat)
 * (Mig3PackedMul, 3 cycles in EX).
 *
 * The operands make the signed, unsigned, mixed and rounded results differ (expected values
 * by P's definitions, computed by a script). vxsat: not set by Q15 products that fit, set by
 * a lane of 0x8000 * 0x8000, read by the very next instruction.
 * After the halting EBREAK: number of expected registers, then pairs register, value.
 */
    .macro EXPECT_REG r, value
    .word \r, \value
    .endm

    .section .text.start, "ax"
    .globl _start
_start:
    li           x1, 0xc0017fff     # halfwords 0xc001 0x7fff
    li           x2, 0x80034001     # halfwords 0x8003 0x4001
    pmulh.h      x3, x1, x2
    pmulhu.h     x4, x1, x2
    pmulhsu.h    x5, x1, x2
    pmulhr.h     x6, x1, x2
    pmulhru.h    x7, x1, x2
    pmulhrsu.h   x8, x1, x2
    pmulq.h      x9, x1, x2
    pmulqr.h     x10, x1, x2
    csrr         x11, vxsat         # 0: every Q15 product fit
    li           x12, 0x80000003    # halfwords 0x8000 0x0003
    li           x13, 0x80004001    # halfwords 0x8000 0x4001
    pmulq.h      x14, x12, x13      # 7fff (saturated) 0001
    csrr         x15, vxsat         # 1
    csrwi        vxsat, 0
    pmulqr.h     x16, x12, x13      # 7fff 0002 (rounded)
    csrr         x17, vxsat         # 1
    ebreak

    .word (expect_end - expect) / 8
expect:
    EXPECT_REG 3,  0x1ffe2000
    EXPECT_REG 4,  0x60022000
    EXPECT_REG 5,  0xdfff2000
    EXPECT_REG 6,  0x1fff2000
    EXPECT_REG 7,  0x60032000
    EXPECT_REG 8,  0xe0002000
    EXPECT_REG 9,  0x3ffd4000
    EXPECT_REG 10, 0x3ffe4000
    EXPECT_REG 11, 0
    EXPECT_REG 14, 0x7fff0001
    EXPECT_REG 15, 1
    EXPECT_REG 16, 0x7fff0002
    EXPECT_REG 17, 1
expect_end:

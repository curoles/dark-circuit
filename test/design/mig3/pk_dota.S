/* Program for TbMig3 with +expect_regs: Mig3's accumulating packed dot products (P
 * extension, draft; assembled with clang's experimental P): PM4ADDA.B, PM2ADDA.H and their
 * unsigned (PMxADDAU) and signed x unsigned (PMxADDASU) forms: rd + the dot product, rd read
 * in EX through ID's rs2 port (Mig3PackedMul, 4 cycles in EX).
 *
 * Accumulators: an immediate, the previous accumulate's rd (its newest writer in MEM/WB, a
 * chain), a word loaded right before (the sum wraps), rd also rs1. A result used at once by
 * an ADD. The operands of the forms as in pk_dot.S, the sums shifted by the accumulator.
 * After the halting EBREAK: number of expected registers, then pairs register, value.
 */
    .macro EXPECT_REG r, value
    .word \r, \value
    .endm

    .section .text.start, "ax"
    .globl _start
_start:
    li           x1, 0x04030201     # bytes 4 3 2 1
    li           x2, 0x281e140a     # bytes 40 30 20 10
    li           x3, 1000
    pm4adda.b    x3, x1, x2         # 1000 + 300 = 1300
    pm4adda.b    x3, x1, x2         # rd just written (MEM/WB): 1600
    add          x4, x3, x0         # x3 at once
    la           x5, word
    lw           x6, 0(x5)          # 0x7ffffffe, loaded right before
    pm4adda.b    x6, x1, x2         # wraps: 0x8000012a
    li           x7, 0x00010002     # halfwords 1, 2
    pm2adda.h    x7, x7, x2         # rd = rs1: 0x00010002 + 2*0x140a + 1*0x281e
    li           x8, 0x80ff7f01     # bytes -128 -1 127 1
    li           x9, 0x80ff8102     # bytes -128 -1 -127 2
    li           x10, 0x10
    pm4addau.b   x10, x8, x9        # 0x10 + 0x17e02
    li           x11, 2
    pm4addasu.b  x11, x8, x9        # 2 + -254
    li           x12, 0x8001ff7f    # halfwords 0x8001 0xff7f
    li           x13, 0x7fff8102    # halfwords 0x7fff 0x8102
    li           x14, 0x100
    pm2adda.h    x14, x12, x13      # 0x100 + 0xc040fdfd
    li           x15, 1
    pm2addau.h   x15, x12, x13      # 1 + 0xc0c0fdfd
    li           x16, 0
    pm2addasu.h  x16, x12, x13      # 0 + 0xbfbffdfd
    ebreak

    .word (expect_end - expect) / 8
expect:
    EXPECT_REG 3,  0x00000640
    EXPECT_REG 4,  0x00000640
    EXPECT_REG 6,  0x8000012a
    EXPECT_REG 7,  0x00015034
    EXPECT_REG 10, 0x00017e12
    EXPECT_REG 11, 0xffffff04
    EXPECT_REG 14, 0xc040fefd
    EXPECT_REG 15, 0xc0c0fdfe
    EXPECT_REG 16, 0xbfbffdfd
expect_end:

    .data
    .balign 4
word:
    .word 0x7ffffffe

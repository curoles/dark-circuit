/* Program for TbMig3 with +expect_regs: Mig3's packed dot products (P extension, draft;
 * assembled with clang's experimental P): PM4ADD.B (four byte products summed into 32 bits),
 * PM2ADD.H (two halfword products), with their unsigned (PMxADDU) and signed x unsigned
 * (PMxADDSU) forms (Mig3PackedMul, 3 cycles in EX).
 *
 * The operands make the signed, unsigned and mixed results differ. A dot product used at
 * once by an ADD (forwarded from EX); a dot product whose rs2 was loaded right before it.
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
    pm4add.b     x3, x1, x2         # 1*10 + 2*20 + 3*30 + 4*40 = 300
    pm2add.h     x4, x1, x2         # 0x0201*0x140a + 0x0403*0x281e
    li           x5, 0x80ff7f01     # bytes -128 -1 127 1
    li           x6, 0x80ff8102     # bytes -128 -1 -127 2
    pm4add.b     x7, x5, x6         # 16384 + 1 - 16129 + 2 = 258
    pm4addu.b    x8, x5, x6         # 128*128 + 255*255 + 127*129 + 1*2
    pm4addsu.b   x9, x5, x6         # -128*128 - 1*255 + 127*129 + 1*2 = -254
    li           x10, 0x8001ff7f    # halfwords 0x8001 0xff7f
    li           x11, 0x7fff8102    # halfwords 0x7fff 0x8102
    pm2add.h     x12, x10, x11
    pm2addu.h    x13, x10, x11
    pm2addsu.h   x14, x10, x11
    add          x15, x14, x0       # x14 at once
    la           x16, word
    lw           x17, 0(x16)        # x2's value
    pm4add.b     x18, x1, x17       # rs2 loaded right before: as x3
    ebreak

    .word (expect_end - expect) / 8
expect:
    EXPECT_REG 3,  0x0000012c
    EXPECT_REG 4,  0x00c91864
    EXPECT_REG 7,  0x00000102
    EXPECT_REG 8,  0x00017e02
    EXPECT_REG 9,  0xffffff02
    EXPECT_REG 12, 0xc040fdfd
    EXPECT_REG 13, 0xc0c0fdfd
    EXPECT_REG 14, 0xbfbffdfd
    EXPECT_REG 15, 0xbfbffdfd
    EXPECT_REG 18, 0x0000012c
expect_end:

    .data
    .balign 4
word:
    .word 0x281e140a

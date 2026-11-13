/* Program for TbMig3 with +expect_regs: Mig3's packed byte products (P extension, draft;
 * assembled with clang's experimental P): PMUL.H.B00, B01, B11, their unsigned forms PMULU
 * and the signed x unsigned PMULSU.H.B00, B11 (Mig3PackedMul, 3 cycles in EX).
 *
 * Every 16-bit lane: the product of one byte of rs1 and one of rs2, its 16 bits in the lane
 * (b00: the low bytes, b11: the high ones, b01: rs1's low byte by rs2's high one). The
 * operands make the signed, unsigned and mixed results differ. A product used at once by
 * the next multiply and by an ADD (forwarded from EX); a multiply whose rs2 was loaded right
 * before it.
 * After the halting EBREAK: number of expected registers, then pairs register, value.
 */
    .macro EXPECT_REG r, value
    .word \r, \value
    .endm

    .section .text.start, "ax"
    .globl _start
_start:
    li           x1, 0x7f80ff01     # lane 1: ah 7f al 80, lane 0: ah ff al 01
    li           x2, 0x01ff8102     # lane 1: bh 01 bl ff, lane 0: bh 81 bl 02
    pmul.h.b00   x3, x1, x2         # 0080 0002: -128*-1, 1*2
    pmulu.h.b00  x4, x1, x2         # 7f80 0002: 128*255
    pmulsu.h.b00 x5, x1, x2         # 8080 0002: -128*255
    pmul.h.b11   x6, x1, x2         # 007f 007f: 127*1, -1*-127
    pmulu.h.b11  x7, x1, x2         # 007f 807f: 255*129
    pmulsu.h.b11 x8, x1, x2         # 007f ff7f: -1*129
    pmul.h.b01   x9, x1, x2         # ff80 ff81: -128*1, 1*-127
    pmulu.h.b01  x10, x1, x2        # 0080 0081: 128*1, 1*129
    pmul.h.b00   x11, x10, x10      # x10 at once: 4000 3f01 (-128*-128, -127*-127)
    add          x12, x11, x0       # x11 at once
    la           x13, word
    lw           x14, 0(x13)        # x2's value
    pmul.h.b11   x15, x1, x14       # rs2 loaded right before: as x6
    ebreak

    .word (expect_end - expect) / 8
expect:
    EXPECT_REG 3,  0x00800002
    EXPECT_REG 4,  0x7f800002
    EXPECT_REG 5,  0x80800002
    EXPECT_REG 6,  0x007f007f
    EXPECT_REG 7,  0x007f807f
    EXPECT_REG 8,  0x007fff7f
    EXPECT_REG 9,  0xff80ff81
    EXPECT_REG 10, 0x00800081
    EXPECT_REG 11, 0x40003f01
    EXPECT_REG 12, 0x40003f01
    EXPECT_REG 15, 0x007f007f
expect_end:

    .data
    .balign 4
word:
    .word 0x01ff8102

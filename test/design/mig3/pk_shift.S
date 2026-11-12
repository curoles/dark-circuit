/* Program for TbMig3 with +expect_regs: Mig3's packed shifts (P extension, draft; assembled
 * with clang's experimental P): PSLLI, PSRLI, PSRAI (.B, .H) by an immediate and PSLL, PSRL,
 * PSRA (.BS, .HS) by rs2[4:0].
 *
 * Every lane shifts alone: bits never cross into the next lane; an arithmetic right shift
 * fills with the lane's sign. By rs2: the amount is rs2[4:0] (higher bits ignored), and an
 * amount of the lane width or more leaves 0, or the sign everywhere. rs2 loaded right before
 * the shift (the interlock reads rs2 of OP-IMM-32); a shifted result used at once (forwarded
 * from EX).
 * After the halting EBREAK: number of expected registers, then pairs register, value.
 */
    .macro EXPECT_REG r, value
    .word \r, \value
    .endm

    .section .text.start, "ax"
    .globl _start
_start:
    li       x1, 0x80017f81         # bytes 80 01 7f 81, halfwords 8001 7f81
    # By an immediate.
    pslli.b  x3, x1, 1              # 00 02 fe 02
    psrli.b  x4, x1, 1              # 40 00 3f 40
    psrai.b  x5, x1, 1              # c0 00 3f c0: -128 -> -64, -127 -> -64
    pslli.h  x6, x1, 4              # 0010 f810
    psrli.h  x7, x1, 4              # 0800 07f8
    psrai.h  x8, x1, 4              # f800 07f8
    # By rs2[4:0].
    li       x2, 3
    psll.bs  x9, x1, x2             # 00 08 f8 08
    psrl.bs  x10, x1, x2            # 10 00 0f 10
    psra.bs  x11, x1, x2            # f0 00 0f f0: -127 >> 3 = -16
    psll.hs  x12, x1, x2            # 0008 fc08
    li       x13, 9                 # >= 8: whole bytes, not halfwords
    psll.bs  x14, x1, x13           # 00 00 00 00
    psra.bs  x15, x1, x13           # ff 00 00 ff
    psrl.hs  x16, x1, x13           # 0040 003f
    li       x17, 31
    psra.hs  x18, x1, x17           # ffff 0000
    li       x19, 0x103             # rs2[4:0] = 3: the bits above are ignored
    psrl.bs  x20, x1, x19           # 10 00 0f 10
    la       x21, word
    lw       x22, 0(x21)            # 2
    psll.hs  x23, x1, x22           # rs2 loaded right before: 0004 fe04
    psrai.b  x24, x5, 1             # x5 forwarded: e0 00 1f e0
    ebreak

    .word (expect_end - expect) / 8
expect:
    EXPECT_REG 3,  0x0002fe02
    EXPECT_REG 4,  0x40003f40
    EXPECT_REG 5,  0xc0003fc0
    EXPECT_REG 6,  0x0010f810
    EXPECT_REG 7,  0x080007f8
    EXPECT_REG 8,  0xf80007f8
    EXPECT_REG 9,  0x0008f808
    EXPECT_REG 10, 0x10000f10
    EXPECT_REG 11, 0xf0000ff0
    EXPECT_REG 12, 0x0008fc08
    EXPECT_REG 14, 0x00000000
    EXPECT_REG 15, 0xff0000ff
    EXPECT_REG 16, 0x0040003f
    EXPECT_REG 18, 0xffff0000
    EXPECT_REG 20, 0x10000f10
    EXPECT_REG 23, 0x0004fe04
    EXPECT_REG 24, 0xe0001fe0
expect_end:

    .data
    .balign 4
word:
    .word 2

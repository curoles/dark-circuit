/* Program for TbMig3 with +expect_regs: Mig3's packed load immediates (P extension, draft;
 * assembled with clang's experimental P): PLI.B (a byte in every byte), PLI.H (a 10-bit
 * signed value in every halfword), PLUI.H (a 10-bit value in every halfword's top 10 bits).
 *
 * Values whose bits are not symmetric, so a field read in the wrong order shows; the most
 * negative and most positive PLI.H values. A li of a constant with equal halfwords, which
 * clang assembles as PLI.H when P is on. A loaded immediate used at once by PADD.H
 * (forwarded from EX).
 * After the halting EBREAK: number of expected registers, then pairs register, value.
 */
    .macro EXPECT_REG r, value
    .word \r, \value
    .endm

    .section .text.start, "ax"
    .globl _start
_start:
    pli.b        x1, -1             # ff ff ff ff
    pli.b        x2, 0x5a           # 5a 5a 5a 5a
    pli.h        x3, -3             # fffd fffd
    pli.h        x4, 511            # 01ff 01ff
    pli.h        x5, -512           # fe00 fe00
    pli.h        x6, 421            # 01a5 01a5
    pli.h        x7, -346           # fea6 fea6
    plui.h       x8, 1              # 0040 0040
    plui.h       x9, 341            # 5540 5540 (341 << 6)
    plui.h       x10, -1            # ffc0 ffc0
    li           x11, 0x00010001    # clang: pli.h x11, 1
    padd.h       x12, x6, x6        # x6 at once: 034a 034a
    ebreak

    .word (expect_end - expect) / 8
expect:
    EXPECT_REG 1,  0xffffffff
    EXPECT_REG 2,  0x5a5a5a5a
    EXPECT_REG 3,  0xfffdfffd
    EXPECT_REG 4,  0x01ff01ff
    EXPECT_REG 5,  0xfe00fe00
    EXPECT_REG 6,  0x01a501a5
    EXPECT_REG 7,  0xfea6fea6
    EXPECT_REG 8,  0x00400040
    EXPECT_REG 9,  0x55405540
    EXPECT_REG 10, 0xffc0ffc0
    EXPECT_REG 11, 0x00010001
    EXPECT_REG 12, 0x034a034a
expect_end:

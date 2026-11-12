/* Program for TbMig3 with +expect_regs: Mig3's saturating packed instructions (P extension,
 * draft; assembled with clang's experimental P): PSADD, PSADDU, PSSUB, PSSUBU, .B and .H,
 * and the vxsat flag they set.
 *
 * A lane that overflows stays at its limit: signed the largest positive or the smallest
 * negative, unsigned all ones (an addition) or 0 (a subtraction); the other lanes keep their
 * sum. vxsat: not set by the wrapping PADD that overflows, nor by a saturating instruction
 * whose lanes reach a limit exactly; set by every saturating instruction that clamps a lane,
 * read by the very next instruction; it stays set (sticky) until written. A saturated result
 * used at once by the next instruction (forwarded from EX).
 * After the halting EBREAK: number of expected registers, then pairs register, value.
 */
    .macro EXPECT_REG r, value
    .word \r, \value
    .endm

    .section .text.start, "ax"
    .globl _start
_start:
    li       x1, 0x7f80ff01         # bytes 7f 80 ff 01, halfwords 7f80 ff01
    li       x2, 0x01807f01         # bytes 01 80 7f 01, halfwords 0180 7f01
    # No vxsat: a wrapping overflow, and limits reached exactly.
    padd.b   x3, x1, x2             # 80 00 7e 02: 7f + 01 wraps
    pssub.b  x4, x1, x2             # 7e 00 80 00: -1 - 127 = -128 exactly
    pssubu.b x5, x1, x2             # 7e 00 80 00
    pssub.h  x6, x1, x2             # 7e00 8000: -255 - 32513 = -32768 exactly
    pssubu.h x7, x1, x2             # 7e00 8000
    csrr     x8, vxsat              # 0
    # Each saturates some lane: vxsat read right after it, then cleared.
    psadd.b  x9, x1, x2             # 7f 80 7e 02: 127 + 1 -> 127, -128 + -128 -> -128
    csrr     x10, vxsat             # 1
    csrwi    vxsat, 0
    psaddu.b x11, x1, x2            # 80 ff ff 02: 128 + 128, 255 + 127 -> 255
    csrr     x12, vxsat             # 1
    csrwi    vxsat, 0
    pssubu.b x13, x2, x1            # 00 00 00 00: 1 - 127, 127 - 255 -> 0
    csrr     x14, vxsat             # 1
    csrwi    vxsat, 0
    psadd.h  x15, x1, x2            # 7fff 7e02: 32640 + 384 -> 32767
    csrr     x16, vxsat             # 1
    csrwi    vxsat, 0
    psaddu.h x17, x1, x2            # 8100 ffff: 65281 + 32513 -> 65535
    csrr     x18, vxsat             # 1
    csrwi    vxsat, 0
    pssub.h  x19, x2, x1            # 8200 7fff: 32513 + 255 -> 32767
    csrr     x20, vxsat             # 1, left set
    # A saturated result forwarded at once; vxsat sticky through a wrapping add.
    psaddu.b x21, x9, x9            # fe ff fc 04: 80 + 80 -> ff
    padd.b   x22, x1, x1            # fe 00 fe 02
    csrr     x23, vxsat             # 1
    ebreak

    .word (expect_end - expect) / 8
expect:
    EXPECT_REG 3,  0x80007e02
    EXPECT_REG 4,  0x7e008000
    EXPECT_REG 5,  0x7e008000
    EXPECT_REG 6,  0x7e008000
    EXPECT_REG 7,  0x7e008000
    EXPECT_REG 8,  0
    EXPECT_REG 9,  0x7f807e02
    EXPECT_REG 10, 1
    EXPECT_REG 11, 0x80ffff02
    EXPECT_REG 12, 1
    EXPECT_REG 13, 0x00000000
    EXPECT_REG 14, 1
    EXPECT_REG 15, 0x7fff7e02
    EXPECT_REG 16, 1
    EXPECT_REG 17, 0x8100ffff
    EXPECT_REG 18, 1
    EXPECT_REG 19, 0x82007fff
    EXPECT_REG 20, 1
    EXPECT_REG 21, 0xfefffc04
    EXPECT_REG 22, 0xfe00fe02
    EXPECT_REG 23, 1
expect_end:

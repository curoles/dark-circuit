/* Program for TbMig3 with +expect_regs: Mig3's first packed SIMD instructions (P extension,
 * draft; assembled with clang's experimental P): PADD.B, PADD.H, PSUB.B, PSUB.H.
 *
 * Every lane wraps alone: a carry or a borrow never crosses into the next lane. Bytes
 * 0xff + 0x01 give 0x00 in their lane and leave the lane above as it was; halfwords the
 * same at 16 bits; subtraction borrows inside a lane only. Results used at once by the next
 * instruction (forwarded from EX), and after a load (the interlock reads rs2 of OP-32).
 * After the halting EBREAK: number of expected registers, then pairs register, value.
 */
    .macro EXPECT_REG r, value
    .word \r, \value
    .endm

    .section .text.start, "ax"
    .globl _start
_start:
    li       x1, 0x7f80ff01
    li       x2, 0x01807f01
    padd.b   x3, x1, x2             # 80 00 7e 02: no byte carries into the next
    padd.h   x4, x1, x2             # 8100 7e02 (0x7f80+0x0180, 0xff01+0x7f01 wraps)
    psub.b   x5, x1, x2             # 7e 00 80 00
    psub.h   x6, x1, x2             # 7e00 8000
    psub.b   x7, x3, x1             # x3 - x1 = x2 lane by lane: 01 80 7f 01
    lui      x8, 0x10               # 0x00010001; not li: with P the assembler makes
    addi     x8, x8, 1              # it PLI.H (packed load immediate, not in Mig3)
    psub.h   x9, x0, x8             # ffff ffff: each halfword borrows alone
    la       x10, word
    lw       x11, 0(x10)            # 0x01010101
    padd.b   x12, x1, x11           # rs2 loaded right before: 80 81 00 02
    ebreak

    .word (expect_end - expect) / 8
expect:
    EXPECT_REG 3,  0x80007e02
    EXPECT_REG 4,  0x81007e02
    EXPECT_REG 5,  0x7e008000
    EXPECT_REG 6,  0x7e008000
    EXPECT_REG 7,  0x01807f01
    EXPECT_REG 9,  0xffffffff
    EXPECT_REG 12, 0x80810002
expect_end:

    .data
    .balign 4
word:
    .word 0x01010101

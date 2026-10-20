/* Program for TbMig2 with +expect_regs: loads and stores, straight-line.
 *
 * Loads: LB and LBU at every byte offset, LH and LHU at offsets 0 and 2, LW, with
 * bytes that have the top bit set (sign extension) and bytes that do not.
 * Stores into buf, read back with LW: SB at every offset (only the low byte of
 * rs2 is written), SH at offsets 0 and 2, SB over a word written by SW.
 * Also: a load used by the next instruction, LW with rd = rs1, a load into x0,
 * a store right after a load.
 * After the halting EBREAK: number of expected registers, then pairs register, value;
 * values are expressions of DATA0 and DATA1 where the assembler can compute them.
 */
    .equ DATA0, 0x80818283      # bytes 83 82 81 80: top bit set
    .equ DATA1, 0x7f017e02      # bytes 02 7e 01 7f: top bit clear

    .macro EXPECT_REG r, value
    .word \r, \value
    .endm

    .section .text.start, "ax"
    .globl _start
_start:
    lla   x1, data

    lb    x2, 0(x1)
    lb    x3, 1(x1)
    lb    x4, 2(x1)
    lb    x5, 3(x1)
    lbu   x6, 3(x1)
    lbu   x7, 0(x1)
    lh    x8, 0(x1)
    lh    x9, 2(x1)
    lhu   x10, 2(x1)
    lw    x11, 0(x1)
    lb    x12, 5(x1)
    lh    x14, 6(x1)

    # SB at every offset of buf word 0; bits above the byte must not be written.
    lla   x13, buf
    addi  x15, x0, 0x7a1
    addi  x16, x0, 0x7b2
    addi  x17, x0, 0x7c3
    addi  x18, x0, 0x7d4
    sb    x15, 0(x13)
    sb    x16, 1(x13)
    sb    x17, 2(x13)
    sb    x18, 3(x13)
    lw    x19, 0(x13)

    # SH at offsets 0 and 2 of buf word 1.
    li    x20, 0x5555a1b2
    li    x21, 0x6666c3d4
    sh    x20, 4(x13)
    sh    x21, 6(x13)
    lw    x22, 4(x13)

    # SB over a word written by SW: the other bytes stay.
    sw    x11, 8(x13)
    sb    x15, 9(x13)
    lw    x23, 8(x13)

    # Load used by the next instruction.
    lw    x24, 0(x1)
    add   x25, x24, x24

    # LW with rd = rs1: the address comes from the old value.
    lla   x26, data
    lw    x26, 0(x26)

    # Load into x0 changes nothing.
    lw    x0, 0(x1)
    add   x27, x0, x0

    # Store right after a load.
    lw    x28, 4(x1)
    sw    x28, 12(x13)
    lw    x29, 12(x13)

    ebreak

    .word (expect_end - expect) / 8
expect:
    EXPECT_REG 2,  (DATA0 & 0xff) - 0x100
    EXPECT_REG 3,  ((DATA0 >> 8) & 0xff) - 0x100
    EXPECT_REG 4,  ((DATA0 >> 16) & 0xff) - 0x100
    EXPECT_REG 5,  ((DATA0 >> 24) & 0xff) - 0x100
    EXPECT_REG 6,  (DATA0 >> 24) & 0xff
    EXPECT_REG 7,  DATA0 & 0xff
    EXPECT_REG 8,  (DATA0 & 0xffff) - 0x10000
    EXPECT_REG 9,  ((DATA0 >> 16) & 0xffff) - 0x10000
    EXPECT_REG 10, (DATA0 >> 16) & 0xffff
    EXPECT_REG 11, DATA0
    EXPECT_REG 12, (DATA1 >> 8) & 0xff
    EXPECT_REG 14, (DATA1 >> 16) & 0xffff
    EXPECT_REG 19, 0xd4c3b2a1
    EXPECT_REG 22, 0xc3d4a1b2
    EXPECT_REG 23, (DATA0 & 0xffff00ff) | 0xa100
    EXPECT_REG 24, DATA0
    EXPECT_REG 25, (DATA0 * 2) & 0xffffffff
    EXPECT_REG 26, DATA0
    EXPECT_REG 27, 0
    EXPECT_REG 29, DATA1
expect_end:

    .data
    .align 2
data:
    .word DATA0, DATA1
buf:
    .word 0, 0, 0, 0

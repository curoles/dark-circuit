/* Program for TbMig1 with +expect_regs: M extension in the pipeline.
 *
 * What riscv-tests rv32um does not check: a division result used by the very next
 * instruction; a division right before a taken branch; a division in the dropped slot
 * after a jump (its rd must not change); minstret counts a division once; the cost of a
 * division in cycles (34 in EX, from mcycle); MULH, MULHSU, MULHU with a negative operand.
 * After the halting EBREAK: number of expected registers, then pairs register, value.
 */
    .macro EXPECT_REG r, value
    .word \r, \value
    .endm

    .section .text.start, "ax"
    .globl _start
_start:
    li     x1, -7
    li     x2, 2
    div    x3, x1, x2           # -3 (toward zero)
    add    x4, x3, x3           # the result right away: -6
    rem    x5, x1, x2           # -1 (sign of the dividend)
    beq    x5, x5, 1f           # taken right after REM
    li     x5, 99               # dropped
1:
    li     x6, 5
    j      2f
    div    x6, x1, x2           # dropped slot: x6 stays 5
2:
    rdinstret x7
    divu   x8, x1, x2           # 0xfffffff9 / 2
    rdinstret x9
    sub    x10, x9, x7          # 2: the first rdinstret and the division
    rdcycle x11
    remu   x12, x1, x2          # 1
    rdcycle x13
    sub    x14, x13, x11        # 1 + 34
    mulh   x15, x1, x2          # high of -14: -1
    mulhsu x16, x1, x2          # high of -7 * 2 (rs1 signed): -1
    mulhu  x17, x1, x2          # high of 0xfffffff9 * 2: 1
    mul    x18, x1, x2          # -14
    ebreak

    .word (expect_end - expect) / 8
expect:
    EXPECT_REG 3,  -3
    EXPECT_REG 4,  -6
    EXPECT_REG 5,  -1
    EXPECT_REG 6,  5
    EXPECT_REG 8,  0xfffffff9 / 2
    EXPECT_REG 10, 2
    EXPECT_REG 12, 1
    EXPECT_REG 14, 35
    EXPECT_REG 15, -1
    EXPECT_REG 16, -1
    EXPECT_REG 17, 1
    EXPECT_REG 18, -14
expect_end:

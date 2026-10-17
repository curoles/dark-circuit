/* Program for TbMig1 with +expect_regs: OP, OP-IMM, LUI and AUIPC, straight-line.
 *
 * Every operation, with a negative operand where signed and unsigned differ;
 * instructions use results of the instructions right before them.
 * After the halting EBREAK: number of expected registers, then pairs register, value.
 * Values are expressions the assembler computes; comparisons and arithmetic
 * shifts are plain numbers.
 */
    .macro EXPECT_REG r, value
    .word \r, \value
    .endm

    .section .text.start, "ax"
    .globl _start
_start:
    addi  x1, x0, 5
    addi  x2, x0, -3
    add   x3, x1, x2
    sub   x4, x1, x2
    sub   x5, x2, x1
    slt   x6, x2, x1          # -3 < 5 signed
    sltu  x7, x2, x1          # 0xfffffffd < 5 unsigned
    xor   x8, x1, x2
    or    x9, x1, x2
    and   x10, x1, x2
    sll   x11, x1, x1
    srl   x12, x2, x1
    sra   x13, x2, x1
    slti  x14, x2, 0
    sltiu x15, x1, -1         # immediate sign-extended, then compared unsigned
    xori  x16, x1, -1
    ori   x17, x0, 0x7ff
    andi  x18, x2, 0xff
    slli  x19, x1, 31
    srli  x20, x2, 28
    srai  x21, x2, 1
    lui   x22, 0x12345
    addi  x22, x22, 0x678
    lui   x23, 0xfffff
here:
    auipc x24, 0
    addi  x0, x0, 1           # x0 stays 0
    add   x25, x0, x0
    ebreak

    .word (expect_end - expect) / 8
expect:
    EXPECT_REG 1,  5
    EXPECT_REG 2,  -3
    EXPECT_REG 3,  5 + -3
    EXPECT_REG 4,  5 - -3
    EXPECT_REG 5,  -3 - 5
    EXPECT_REG 6,  1
    EXPECT_REG 7,  0
    EXPECT_REG 8,  5 ^ -3
    EXPECT_REG 9,  5 | -3
    EXPECT_REG 10, 5 & -3
    EXPECT_REG 11, 5 << 5
    EXPECT_REG 12, 0xfffffffd >> 5
    EXPECT_REG 13, -1                  # -3 >> 5 arithmetic
    EXPECT_REG 14, 1
    EXPECT_REG 15, 1
    EXPECT_REG 16, ~5
    EXPECT_REG 17, 0x7ff
    EXPECT_REG 18, -3 & 0xff
    EXPECT_REG 19, 0x80000000          # 5 << 31
    EXPECT_REG 20, 0xfffffffd >> 28
    EXPECT_REG 21, -2                  # -3 >> 1 arithmetic
    EXPECT_REG 22, 0x12345678
    EXPECT_REG 23, 0xfffff000
    EXPECT_REG 24, here
    EXPECT_REG 25, 0
expect_end:

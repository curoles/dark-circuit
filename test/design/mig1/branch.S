/* Program for TbMig1 with +expect_regs: branches, JAL and JALR.
 *
 * Every branch type taken and not taken, with operands -1 and 1 where signed and
 * unsigned compare differently, and with equal operands.
 * - Not taken: the next instruction must run and sets its bit in x10 (expect all 6).
 * - Taken, and every jump: the next instruction must be skipped; it would set its
 *   bit in x11 (branches) or x17 (jumps), expect 0.
 * Also: a backward loop, jumps right after jumps, an EBREAK that must be skipped,
 * return addresses of JAL and JALR, JALR with odd rs1 and with rd = rs1.
 * After the halting EBREAK: number of expected registers, then pairs register, value.
 */
    .macro EXPECT_REG r, value
    .word \r, \value
    .endm

    .macro NOT_TAKEN br, a, b, bit
    \br   \a, \b, 1f
    ori   x10, x10, \bit
1:
    .endm

    .macro TAKEN br, a, b, bit
    \br   \a, \b, 1f
    ori   x11, x11, \bit
1:
    .endm

    .section .text.start, "ax"
    .globl _start
_start:
    addi  x1, x0, -1
    addi  x2, x0, 1
    addi  x3, x0, -1
    addi  x10, x0, 0
    addi  x11, x0, 0
    addi  x17, x0, 0

    NOT_TAKEN beq,  x1, x2, 0x01
    NOT_TAKEN bne,  x1, x3, 0x02
    NOT_TAKEN blt,  x2, x1, 0x04      # 1 < -1 signed: no
    NOT_TAKEN bge,  x1, x2, 0x08
    NOT_TAKEN bltu, x1, x2, 0x10      # 0xffffffff < 1 unsigned: no
    NOT_TAKEN bgeu, x2, x1, 0x20

    TAKEN     beq,  x1, x3, 0x01
    TAKEN     bne,  x1, x2, 0x02
    TAKEN     blt,  x1, x2, 0x04      # -1 < 1 signed
    TAKEN     bge,  x2, x1, 0x08
    TAKEN     bge,  x1, x3, 0x10      # equal
    TAKEN     bltu, x2, x1, 0x20      # 1 < 0xffffffff unsigned
    TAKEN     bgeu, x1, x2, 0x40
    TAKEN     bgeu, x1, x3, 0x80      # equal

    # Backward loop, 5 times.
    addi  x12, x0, 5
    addi  x13, x0, 0
loop:
    addi  x13, x13, 3
    addi  x12, x12, -1
    bnez  x12, loop

    # Jump right after jump (jal x0).
    j     chain1
    ori   x17, x17, 0x01
chain1:
    j     chain2
    ori   x17, x17, 0x02
chain2:

    # EBREAK after a jump is dropped, it must not halt.
    j     skip_ebreak
    ebreak
skip_ebreak:

    # JAL: rd is the address of the next instruction.
    jal   x14, jal_target
ret_jal:
    ori   x17, x17, 0x04
jal_target:

    # JALR with odd rs1: bit 0 of the target is ignored.
    la    x16, jalr_target
    addi  x16, x16, 1
    jalr  x15, 0(x16)
ret_jalr:
    ori   x17, x17, 0x08
jalr_target:

    # JALR with rd = rs1: the target comes from the old value.
    la    x18, rd_rs1_target
    jalr  x18, 0(x18)
ret_rd_rs1:
    ori   x17, x17, 0x10
rd_rs1_target:

    # JALR with offset, rd = x0 (jr).
    la    x19, offset_target - 8
    jalr  x0, 8(x19)
    ori   x17, x17, 0x20
offset_target:

    ebreak

    .word (expect_end - expect) / 8
expect:
    EXPECT_REG 10, 0x3f
    EXPECT_REG 11, 0
    EXPECT_REG 12, 0
    EXPECT_REG 13, 15
    EXPECT_REG 14, ret_jal
    EXPECT_REG 15, ret_jalr
    EXPECT_REG 17, 0
    EXPECT_REG 18, ret_rd_rs1
expect_end:

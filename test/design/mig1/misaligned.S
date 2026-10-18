/* Program for TbMig1 with +expect_illegal: JALR to an address that is not 4-byte aligned.
 *
 * The JALR at 0xc must not complete: the core halts there with illegal=1 and x1
 * keeps 7 (+expect_halt_pc=c, +expect_regs with the table after the JALR).
 * norelax keeps lla as auipc + addi, so the JALR stays at 0xc.
 * If the core ignored bit 1 of the target, it would reach the EBREAK and halt
 * with illegal=0.
 */
    .macro EXPECT_REG r, value
    .word \r, \value
    .endm

    .option norelax
    .section .text.start, "ax"
    .globl _start
_start:
    addi  x1, x0, 7
    lla   x2, wrong + 2
    jalr  x1, 0(x2)

    .word (expect_end - expect) / 8
expect:
    EXPECT_REG 1, 7
expect_end:

wrong:
    ebreak

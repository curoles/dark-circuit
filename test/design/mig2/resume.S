/* Program for TbMig2 with +resumes=2 +expect_regs: debug port and resume.
 *
 * At the first two EBREAKs the testbench reads a0 through the debug port, writes
 * a0 + 0x100 and resumes; the core continues with the next instruction. a1 and a2 copy
 * a0 after each resume, so they show that the debug write reached the register file
 * and that execution continued right after the EBREAK. The third EBREAK ends the run.
 * After the halting EBREAK: number of expected registers, then pairs register, value.
 */
    .macro EXPECT_REG r, value
    .word \r, \value
    .endm

    .section .text.start, "ax"
    .globl _start
_start:
    addi  a0, x0, 5
    ebreak                  # debugger: a0 <- 0x105, resume
    addi  a1, a0, 0
    ebreak                  # debugger: a0 <- 0x205, resume
    addi  a2, a0, 0
    ebreak

    .word (expect_end - expect) / 8
expect:
    EXPECT_REG 10, 5 + 0x200    # a0
    EXPECT_REG 11, 5 + 0x100    # a1
    EXPECT_REG 12, 5 + 0x200    # a2
expect_end:

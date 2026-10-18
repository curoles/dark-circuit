/* Program for TbMig1 with +expect_illegal: instructions that stop the core.
 *
 * One case per build, selected with -D:
 * - CASE_ECALL: ECALL (Mig1 has no traps, ECALL is a fault),
 * - CASE_ZERO:  the all-zeros word, illegal in RISC-V,
 * - CASE_ONES:  the all-ones word, illegal in RISC-V,
 * - CASE_CSR_UNKNOWN:  csrr of a CSR that Mig1 does not have (custom 0x7c0),
 * - CASE_CSR_READONLY: csrw of cycle, a read-only CSR.
 * The instruction at 0xc must not complete: the core halts there with illegal=1 and
 * x1 keeps 7 (+expect_halt_pc=c, +expect_regs with the table after the instruction).
 * The two instructions before it keep the layout of misaligned.S.
 */
    .macro EXPECT_REG r, value
    .word \r, \value
    .endm

    .option norelax
    .section .text.start, "ax"
    .globl _start
_start:
    addi  x1, x0, 7
    addi  x2, x0, 0
    addi  x3, x0, 0
#if defined(CASE_ECALL)
    ecall
#elif defined(CASE_ZERO)
    .word 0x00000000
#elif defined(CASE_ONES)
    .word 0xffffffff
#elif defined(CASE_CSR_UNKNOWN)
    csrr  x1, 0x7c0
#elif defined(CASE_CSR_READONLY)
    csrw  cycle, x1
#else
#error "define CASE_ECALL, CASE_ZERO, CASE_ONES, CASE_CSR_UNKNOWN or CASE_CSR_READONLY"
#endif

    .word (expect_end - expect) / 8
expect:
    EXPECT_REG 1, 7
expect_end:

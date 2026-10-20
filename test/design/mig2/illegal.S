/* Program for TbMig2 with +expect_trap: instructions that trap.
 *
 * One case per build, selected with -D:
 * - CASE_ECALL: ECALL (environment call from machine mode, mtval 0),
 * - CASE_ZERO:  the all-zeros word, illegal in RISC-V,
 * - CASE_ONES:  the all-ones word, illegal in RISC-V,
 * - CASE_CSR_UNKNOWN:  csrr of a CSR that Mig2 does not have (custom 0x7c0),
 * - CASE_CSR_READONLY: csrw of cycle, a read-only CSR.
 * Illegal instructions have the instruction word as mtval; x13 loads it from memory.
 * The instruction at `fault` traps: it writes nothing (x1 keeps 7, memory unchanged
 * with +expect_mem_unchanged). The handler copies mcause to x10, mepc to x11, and
 * mtval minus the expected mtval (x13) to x12, then halts.
 * Expected: x10 = CAUSE, x11 = fault, x12 = 0.
 */
    .macro EXPECT_REG r, value
    .word \r, \value
    .endm

    .section .text.start, "ax"
    .globl _start
_start:
    la    t0, handler
    csrw  mtvec, t0
    addi  x1, x0, 7
#if defined(CASE_ECALL)
    .equ  CAUSE, 11                 # environment call from M-mode
    li    x13, 0
#else
    .equ  CAUSE, 2                  # illegal instruction
    la    x3, fault
    lw    x13, 0(x3)
#endif
fault:
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
    ebreak                          # not reached: the instruction before traps

handler:
    csrr  x10, mcause
    csrr  x11, mepc
    csrr  x12, mtval
    sub   x12, x12, x13
    ebreak

    .word (expect_end - expect) / 8
expect:
    EXPECT_REG 1,  7
    EXPECT_REG 10, CAUSE
    EXPECT_REG 11, fault
    EXPECT_REG 12, 0
expect_end:

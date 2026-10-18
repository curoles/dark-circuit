/* Mig1 environment of riscv-tests (test/third_party/riscv-tests).
 *
 * Every riscv-tests test includes riscv_test.h. The standard environment (env/p of
 * riscv-tests) sets up CSRs and reports the result to a host through memory word
 * tohost; Mig1 has no CSRs, so this one is minimal:
 * - the test starts at _start in .text.start, the reset address (sw/riscv/mig1.ld);
 * - the result is in a0 at EBREAK, coded like tohost: 0 is pass, (case << 1) | 1 is
 *   case number `case` failed (TESTNUM, register gp, is the case number);
 * - TbMig1 with +riscv_test reads a0 through the debug port at the halt.
 * Tests of RV64 (rv64ui) are included by rv32ui as RV32 tests, so both are RV32U.
 */
#ifndef MIG1_RISCV_TEST_H
#define MIG1_RISCV_TEST_H

#define RVTEST_RV32U                                                    \
    .macro init;                                                        \
    .endm

#define RVTEST_RV64U RVTEST_RV32U

#define TESTNUM gp

#define RVTEST_CODE_BEGIN                                               \
    .section .text.start, "ax";                                         \
    .globl _start;                                                      \
_start:                                                                 \
    init;

#define RVTEST_CODE_END                                                 \
    unimp

#define RVTEST_PASS                                                     \
    fence;                                                              \
    li a0, 0;                                                           \
    ebreak

/* Case 0 does not exist: wait forever rather than report a pass. */
#define RVTEST_FAIL                                                     \
    fence;                                                              \
1:  beqz TESTNUM, 1b;                                                   \
    sll a0, TESTNUM, 1;                                                 \
    or a0, a0, 1;                                                       \
    ebreak

#define RVTEST_DATA_BEGIN                                               \
    .align 4

#define RVTEST_DATA_END                                                 \
    .align 4

#endif

/* Program for TbMig1 with +expect_trap: access to an address that is not aligned.
 *
 * One case per build, selected with -D:
 * - CASE_JALR: JALR to an address with bit 1 set (instructions are 4-byte aligned),
 * - CASE_LW:   LW from an address with bit 1 set,
 * - CASE_SH:   SH to an odd address.
 * The instruction at `fault` traps: it writes nothing (x1 keeps 7, memory unchanged
 * with +expect_mem_unchanged). The handler copies mcause to x10, mepc to x11, and
 * mtval minus the expected mtval (x13, the bad address) to x12, then halts.
 * Expected: x10 = CAUSE, x11 = fault, x12 = 0. If the core ignored the low address
 * bits, the JALR would reach the EBREAK at `target` and the LW and SH would complete:
 * the run ends without a trap.
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
#if defined(CASE_JALR)
    .equ  CAUSE, 0                  # misaligned fetch
    la    x2, target + 2
    mv    x13, x2
fault:
    jalr  x1, 0(x2)
#elif defined(CASE_LW)
    .equ  CAUSE, 4                  # misaligned load
    la    x2, target + 2
    mv    x13, x2
fault:
    lw    x1, 0(x2)
#elif defined(CASE_SH)
    .equ  CAUSE, 6                  # misaligned store
    la    x2, target + 1
    mv    x13, x2
fault:
    sh    x1, 0(x2)
#else
#error "define CASE_JALR, CASE_LW or CASE_SH"
#endif
    ebreak                          # not reached: the instruction before traps

target:
    ebreak

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

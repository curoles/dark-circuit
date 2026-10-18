/* Program for TbMig1 with +expect_illegal: access to an address that is not aligned.
 *
 * One case per build, selected with -D:
 * - CASE_JALR: JALR to an address with bit 1 set (instructions are 4-byte aligned),
 * - CASE_LW:   LW from an address with bit 1 set,
 * - CASE_SH:   SH to an odd address.
 * The instruction at 0xc must not complete: the core halts there with illegal=1 and
 * x1 keeps 7 (+expect_halt_pc=c, +expect_regs with the table after the instruction).
 * norelax keeps lla as auipc + addi, so the instruction stays at 0xc.
 * If the core ignored the low address bits, the JALR would reach the EBREAK and the
 * LW and SH would complete; then the core halts later or with illegal=0.
 */
    .macro EXPECT_REG r, value
    .word \r, \value
    .endm

    .option norelax
    .section .text.start, "ax"
    .globl _start
_start:
    addi  x1, x0, 7
#if defined(CASE_JALR)
    lla   x2, wrong + 2
    jalr  x1, 0(x2)
#elif defined(CASE_LW)
    lla   x2, wrong + 2
    lw    x1, 0(x2)
#elif defined(CASE_SH)
    lla   x2, wrong + 1
    sh    x1, 0(x2)
#else
#error "define CASE_JALR, CASE_LW or CASE_SH"
#endif

    .word (expect_end - expect) / 8
expect:
    EXPECT_REG 1, 7
expect_end:

wrong:
    ebreak

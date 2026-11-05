/* Program for TbMig3 with +expect_trap +expect_regs: LR.W and SC.W (Zalrsc), the
 * reservation of Mig3Atomic, in the corners of the pipeline.
 *
 * foo and bar are the two words of one cache line, baz a word in another line that no
 * instruction before touches (a miss). The retire check also checks every SC against a
 * reservation of its own and every store the memory takes; the table at the end checks
 * the results:
 *  1. SC without a reservation fails (a0 = 1) and writes nothing (a1 = foo = 0).
 *  2. LR then SC succeeds (a2 = 0, foo = a3 = 0x123); the SC ended the reservation, a
 *     second SC fails (a4 = 1).
 *  3. SC to another word than the LR's fails (a5 = 1), also in the same line: the
 *     reservation is one word.
 *  4. A trap between LR and SC ends the reservation: ECALL, the handler returns, the SC
 *     fails (a6 = 1).
 *  5. Back to back: LR's word used at once (load-use, t3 = 0x124), SC right after the
 *     add, its result used at once (it comes in MEM/WB: the interlock waits a clock as
 *     after a load; t4 = 0, a7 = 0x124, s2 = foo = 0x124).
 *  6. An LR on the wrong path reserves nothing: a forward branch, taken (guessed not
 *     taken, EX redirects), jumps over it; the SC fails (s3 = 1).
 *  7. An SC that waits in EX (the load before it waits in MEM/WB for a miss) succeeds
 *     (s5 = 0, foo = 1).
 *  8. A store of this hart to the reserved word keeps the reservation (s6 = 0, foo = 1).
 *  9. The counting loop of riscv-tests (lr, add, sc, bnez) 16 times on bar: s7 = 48.
 * 10. A misaligned LR traps (cause 4, mtval foo + 2); then an LR reserves foo and a
 *     misaligned SC traps (cause 6, mtval foo + 1, in foo's word): neither writes rd (s8
 *     keeps 7) nor memory.
 * 11. The misaligned SC's trap ended the reservation of the LR before it: the SC fails
 *     (ra = 1).
 * The handler shifts every mcause into s10 (0xb, 4, 6: s10 = 0xb46), keeps the last two
 * mtval in s9 and s11, and returns to mepc + 4.
 */
    .macro EXPECT_REG r, value
    .word \r, \value
    .endm

    .section .text.start, "ax"
    .globl _start
_start:
    la    t0, handler
    csrw  mtvec, t0
    la    s0, foo
    la    s1, bar
    la    s4, baz
    li    s10, 0
    li    s11, 0

    # 1. SC without a reservation.
    li    t1, 0x5a5a
    sc.w  a0, t1, (s0)
    lw    a1, 0(s0)

    # 2. LR, SC, a second SC.
    lr.w  t2, (s0)
    li    t1, 0x123
    sc.w  a2, t1, (s0)
    lw    a3, 0(s0)
    sc.w  a4, t1, (s0)

    # 3. SC to the other word of the line.
    lr.w  t2, (s0)
    sc.w  a5, t1, (s1)

    # 4. A trap between LR and SC.
    lr.w  t2, (s0)
    ecall
    sc.w  a6, t1, (s0)

    # 5. Back to back, results used at once.
    lr.w  t3, (s0)
    addi  t3, t3, 1
    sc.w  t4, t3, (s0)
    add   a7, t4, t3
    lw    s2, 0(s0)

    # 6. An LR on the wrong path.
    li    t1, 1
    bnez  t1, 1f
    lr.w  t2, (s0)
1:  sc.w  s3, t1, (s0)

    # 7. SC waits in EX behind a load that misses.
    lr.w  t2, (s0)
    lw    t2, 0(s4)
    sc.w  s5, t1, (s0)

    # 8. A store of this hart to the reserved word.
    lr.w  t2, (s0)
    sw    zero, 0(s0)
    sc.w  s6, t1, (s0)

    # 9. The counting loop.
    li    t0, 16
2:  lr.w  t2, (s1)
    addi  t2, t2, 3
    sc.w  t2, t2, (s1)
    bnez  t2, 2b
    addi  t0, t0, -1
    bnez  t0, 2b
    lw    s7, 0(s1)

    # 10. A misaligned LR; then a reservation of foo and a misaligned SC.
    li    s8, 7
    addi  t6, s0, 2
    lr.w  s8, (t6)
    lr.w  t2, (s0)
    addi  t6, s0, 1
    sc.w  s8, t1, (t6)

    # 11. The SC after the misaligned SC.
    sc.w  ra, t1, (s0)
    ebreak

    .word (expect_end - expect) / 8
expect:
    EXPECT_REG 10, 1            # a0
    EXPECT_REG 11, 0            # a1
    EXPECT_REG 12, 0            # a2
    EXPECT_REG 13, 0x123        # a3
    EXPECT_REG 14, 1            # a4
    EXPECT_REG 15, 1            # a5
    EXPECT_REG 16, 1            # a6
    EXPECT_REG 28, 0x124        # t3
    EXPECT_REG 29, 0            # t4
    EXPECT_REG 17, 0x124        # a7
    EXPECT_REG 18, 0x124        # s2
    EXPECT_REG 19, 1            # s3
    EXPECT_REG 21, 0            # s5
    EXPECT_REG 22, 0            # s6
    EXPECT_REG 23, 48           # s7
    EXPECT_REG 5,  0            # t0
    EXPECT_REG 24, 7            # s8
    EXPECT_REG 26, 0xb46        # s10
    EXPECT_REG 25, foo + 2      # s9
    EXPECT_REG 27, foo + 1      # s11
    EXPECT_REG 1,  1            # ra
expect_end:

handler:
    slli  s10, s10, 4
    csrr  t5, mcause
    or    s10, s10, t5
    mv    s9, s11
    csrr  s11, mtval
    csrr  t5, mepc
    addi  t5, t5, 4
    csrw  mepc, t5
    mret

    .data
    .balign 64
foo:
    .word 0
bar:
    .word 0
    .balign 64
baz:
    .word 0x77

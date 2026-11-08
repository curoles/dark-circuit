/* Program for TbMig3 with +expect_trap +expect_regs: the Timer of Mig3Cpu, its interrupt on
 * PLIC source MIG3_TIMER_SOURCE, taken by a handler.
 *
 *  1. Registers: mtimecmp's high word reads all ones after reset (s4), a write of its low word
 *     reads back (s5), two reads of mtime in a row differ (it counts every clock, s6 = 1).
 *  2. Periodic: the program sets mtimecmp = mtime + PERIOD the RV32 way (the low word all
 *     ones, the high word, then the low word: no alarm in between), enables the source at the
 *     PLIC, MEIE and MIE, and waits for N interrupts. The handler (mcause in s3) claims (the
 *     ID must be MIG3_TIMER_SOURCE), checks that mtime has reached mtimecmp (no early
 *     interrupt), moves mtimecmp on by PERIOD, reads mtimecmp back, then completes. The
 *     Timer's line drops one clock after the move; without the read the complete, the next
 *     store, reaches the PLIC in that clock, the source is still high and pends again (a
 *     fourth interrupt). The read is answered only after the Timer took the move, and the
 *     complete leaves after the answer: the rule for software (kb rtl/design/mig3/timer).
 *     The last one sets mtimecmp's high word to all ones (no alarm). Errors into s2: 1 a
 *     wrong ID, 2 an early interrupt. s1 counts the interrupts.
 *  3. A wait of more than 3 * PERIOD clocks: still N interrupts (s7), none without an alarm.
 */
#include "mig3_config.h"

    .equ  PERIOD, 200               # clocks between the alarms
    .equ  N, 3                      # interrupts

    .macro EXPECT_REG r, value
    .word \r, \value
    .endm

    .section .text.start, "ax"
    .globl _start
_start:
    la    t0, handler
    csrw  mtvec, t0
    li    s1, 0
    li    s2, 0
    li    s3, 0
    li    a0, MIG3_TIMER_MTIMECMP
    li    a1, MIG3_TIMER_MTIME

    # 1. Registers.
    lw    s4, 4(a0)                 # all ones after reset
    li    t1, 0x12345678
    sw    t1, 0(a0)
    lw    s5, 0(a0)                 # 0x12345678
    li    t1, -1
    sw    t1, 0(a0)                 # all ones again: no alarm
    lw    t1, 0(a1)
    lw    t2, 0(a1)
    sltu  s6, t1, t2                # mtime counted between the reads: 1

    # 2. Periodic interrupts.
    li    t0, MIG3_PLIC_PRIORITY(MIG3_TIMER_SOURCE)
    li    t1, 1
    sw    t1, 0(t0)                 # the Timer's source: priority 1
    li    t0, MIG3_PLIC_ENABLE
    li    t1, 1 << MIG3_TIMER_SOURCE
    sw    t1, 0(t0)                 # ... enabled for context 0 (threshold 0)
    li    t0, 0x800
    csrs  mie, t0                   # MEIE
    lw    t1, 0(a1)                 # mtime's low word (its high word is 0 in this test)
    addi  t1, t1, PERIOD
    li    t2, -1
    sw    t2, 0(a0)                 # mtimecmp: the low word all ones (no alarm meanwhile),
    sw    zero, 4(a0)               # the high word,
    sw    t1, 0(a0)                 # the low word: the alarm
    csrsi mstatus, 8                # MIE
    li    t1, N
1:  blt   s1, t1, 1b                # wait for N interrupts

    # 3. No interrupt without an alarm.
    li    t1, 3 * PERIOD
2:  addi  t1, t1, -1
    bnez  t1, 2b
    mv    s7, s1
    ebreak

    .word (expect_end - expect) / 8
expect:
    EXPECT_REG 9,  N                # s1
    EXPECT_REG 18, 0                # s2
    EXPECT_REG 19, 0x8000000b       # s3: machine external interrupt
    EXPECT_REG 20, 0xffffffff       # s4
    EXPECT_REG 21, 0x12345678       # s5
    EXPECT_REG 22, 1                # s6
    EXPECT_REG 23, N                # s7
expect_end:

    # The handler, after the table (the table follows the halting EBREAK).
handler:
    csrr  s3, mcause
    li    t3, MIG3_PLIC_CLAIM
    lw    t4, 0(t3)                 # claim
    li    t5, MIG3_TIMER_SOURCE
    beq   t4, t5, 3f
    ori   s2, s2, 1                 # a wrong ID
3:  lw    t5, 0(a1)                 # mtime's low word
    lw    t6, 0(a0)                 # mtimecmp's low word
    bgeu  t5, t6, 4f
    ori   s2, s2, 2                 # early: mtime has not reached mtimecmp
4:  addi  s1, s1, 1
    li    t5, N
    bge   s1, t5, 5f
    addi  t6, t6, PERIOD
    sw    t6, 0(a0)                 # the next alarm
    j     6f
5:  li    t5, -1
    sw    t5, 4(a0)                 # no alarm: the high word all ones
6:  lw    t5, 0(a0)                 # read the Timer back: its line has dropped
    sw    t4, 0(t3)                 # complete, after mtimecmp moved
    mret

/* Program for TbMig3 with +expect_trap +expect_regs: WFI, woken by the Timer's interrupt
 * through the PLIC (source MIG3_TIMER_SOURCE, enabled at the PLIC and in mie.MEIE).
 *
 *  1. MIE = 0, an alarm PERIOD clocks ahead: WFI sleeps until the alarm (mcycle moves by at
 *     least PERIOD / 2 across it: s1 = 1) and no trap is taken (MIE 0: the program goes on
 *     after the WFI). Then CLEAR: claim, alarm off, read back, complete.
 *  2. An interrupt already pending (an alarm in the past, mip.MEIP polled): WFI does not
 *     sleep (mcycle moves by less than SHORT: s2 = 1). CLEAR.
 *  3. MIE = 1, an alarm ahead, WFI at w3: the interrupt is taken after it, on the next
 *     instruction (the handler's mepc is w3 + 4: s3 = 0).
 *  4. MIE set right before the WFI at w4 while an interrupt is pending: it would be taken on
 *     the WFI itself, which instead completes, and the next instruction takes it (mepc
 *     w4 + 4: s7 = 0). The idle loop `wfi; beqz flag` ends: the handler sets the flag (s4).
 *     Had the WFI been interrupted, MRET would return to it and it would sleep for good.
 * The handler counts in s5 (2 in all), keeps mepc in s6, sets s4 and clears the interrupt.
 */
#include "mig3_config.h"

    .equ  PERIOD, 300               # clocks to the alarm
    .equ  SHORT, 20                 # clocks of a WFI that does not sleep, at most

    .macro EXPECT_REG r, value
    .word \r, \value
    .endm

    /* Claim, alarm off, read the Timer back (its line drops), complete. */
    .macro CLEAR
    lw    t4, 0(a2)                 # claim
    li    t5, -1
    sw    t5, 4(a0)                 # mtimecmp's high word all ones: no alarm
    lw    t5, 0(a0)                 # read back
    sw    t4, 0(a2)                 # complete
    .endm

    /* An alarm \delta clocks after now (mtime's high word is 0 in this test). */
    .macro ALARM delta
    lw    t1, 0(a1)
    addi  t1, t1, \delta
    li    t2, -1
    sw    t2, 0(a0)                 # the low word all ones (no alarm meanwhile),
    sw    zero, 4(a0)               # the high word,
    sw    t1, 0(a0)                 # the low word
    .endm

    .section .text.start, "ax"
    .globl _start
_start:
    la    t0, handler
    csrw  mtvec, t0
    li    a0, MIG3_TIMER_MTIMECMP
    li    a1, MIG3_TIMER_MTIME
    li    a2, MIG3_PLIC_CLAIM
    li    s4, 0
    li    s5, 0
    li    t0, MIG3_PLIC_PRIORITY(MIG3_TIMER_SOURCE)
    li    t1, 1
    sw    t1, 0(t0)                 # the Timer's source: priority 1
    li    t0, MIG3_PLIC_ENABLE
    li    t1, 1 << MIG3_TIMER_SOURCE
    sw    t1, 0(t0)                 # ... enabled for context 0 (threshold 0)
    li    t0, 0x800
    csrs  mie, t0                   # MEIE; MIE stays 0

    # 1. WFI sleeps until the alarm; MIE 0: no trap.
    ALARM PERIOD
    csrr  t1, mcycle
    wfi
    csrr  t2, mcycle
    sub   t2, t2, t1
    sltiu t3, t2, PERIOD / 2
    xori  s1, t3, 1                 # slept: 1
    CLEAR

    # 2. Pending already: WFI does not sleep.
    sw    zero, 0(a0)               # mtimecmp = 0 (the high word is all ones from CLEAR:
    sw    zero, 4(a0)               # the low word first, then the high word): due at once
1:  csrr  t0, mip
    srli  t0, t0, 11
    andi  t0, t0, 1
    beqz  t0, 1b                    # wait for MEIP
    csrr  t1, mcycle
    wfi
    csrr  t2, mcycle
    sub   t2, t2, t1
    sltiu s2, t2, SHORT             # did not sleep: 1
    CLEAR

    # 3. MIE = 1: the interrupt is taken after the WFI.
    ALARM PERIOD
    csrsi mstatus, 8                # MIE
w3: wfi
    la    t1, w3 + 4
    sub   s3, s6, t1                # mepc was w3 + 4: 0

    # 4. MIE set right before the WFI with the interrupt pending: the WFI is not interrupted.
    csrci mstatus, 8                # MIE 0
    li    s4, 0
    sw    zero, 0(a0)               # due at once (as in 2)
    sw    zero, 4(a0)
2:  csrr  t0, mip
    srli  t0, t0, 11
    andi  t0, t0, 1
    beqz  t0, 2b                    # wait for MEIP
    csrsi mstatus, 8                # MIE: an interrupt is due on the next instruction, the WFI
w4: wfi
    beqz  s4, w4                    # the idle loop: ends when the handler set the flag
    la    t1, w4 + 4
    sub   s7, s6, t1                # mepc was w4 + 4: 0
    ebreak

    .word (expect_end - expect) / 8
expect:
    EXPECT_REG 9,  1                # s1: slept until the alarm
    EXPECT_REG 18, 1                # s2: did not sleep with an interrupt pending
    EXPECT_REG 19, 0                # s3: taken after the WFI
    EXPECT_REG 20, 1                # s4: the idle loop's flag
    EXPECT_REG 21, 2                # s5: interrupts taken
    EXPECT_REG 23, 0                # s7: not taken on the WFI itself
expect_end:

    # The handler, after the table (the table follows the halting EBREAK).
handler:
    addi  s5, s5, 1
    csrr  s6, mepc
    li    s4, 1
    CLEAR
    mret

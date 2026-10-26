/* Program for TbMig2 with +expect_trap +expect_regs: conditional branches in the corners of
 * the pipeline, for branch prediction in ID (static: backward taken, forward not taken).
 *
 * - Every pair of guess and outcome: a backward loop (taken, the last time not), a forward
 *   branch taken and not taken, a backward branch not taken (guessed taken: the
 *   instructions at its target must not retire).
 * - A backward branch that waits in ID for load data (load-use), and one that waits
 *   behind a division: each redirects once, when it moves to EX.
 * - A backward branch on the wrong path, right after a taken branch: it must not redirect.
 * - Branches back to back: a backward branch at the target of a taken branch.
 * - Taken branches to addresses not divisible by 4, forward and backward: misaligned fetch
 *   traps; the handler adds up mtval - mepc (the offsets of the branches) and the mepc
 *   relative to the first of them, and continues after the branch.
 * Instructions that must not retire set bits in x17 (expect 0), instructions that must
 * retire set bits in x10; targets count their runs. Anything unexpected ends at `fail`,
 * an EBREAK without a register table: the run fails. After the halting EBREAK: number of
 * expected registers, then pairs register, value.
 */
    .option norelax

    .macro EXPECT_REG r, value
    .word \r, \value
    .endm

    .section .text.start, "ax"
    .globl _start
_start:
    j     start
fail:
    ebreak
    j     fail
start:
    la    x30, handler
    csrw  mtvec, x30
    addi  x10, x0, 0
    addi  x11, x0, 0
    addi  x12, x0, 0
    addi  x13, x0, 0
    addi  x17, x0, 0
    addi  x24, x0, 0            # sum of mepc - mis_fwd of the traps
    addi  x28, x0, 0            # traps
    addi  x29, x0, 0            # sum of mtval - mepc of the traps

    # Backward loop: taken 9 times, then not taken.
    addi  x5, x0, 10
    addi  x6, x0, 0
loop:
    addi  x6, x6, 1
    addi  x5, x5, -1
    bnez  x5, loop

    # Forward branches, taken and not taken.
    beq   x0, x0, 1f
    ori   x17, x17, 0x01
1:
    bne   x0, x0, 1f
    ori   x10, x10, 0x01
1:

    # Backward branch not taken: its target must not retire.
    j     2f
1:
    ori   x17, x17, 0x02        # target of the backward branch
    j     3f
2:
    bne   x0, x0, 1b
    ori   x10, x10, 0x02
3:

    # Backward branch that waits in ID for load data, taken.
    la    x8, one
    j     5f
4:
    addi  x11, x11, 1           # its target
    j     6f
5:
    lw    x7, 0(x8)
    bnez  x7, 4b                # load-use: one cycle in ID, then taken
    ori   x17, x17, 0x04
6:

    # Backward branch behind a division, taken.
    li    x8, 100
    li    x9, 7
    j     8f
7:
    addi  x12, x12, 1           # its target
    j     9f
8:
    div   x26, x8, x9
    blt   x0, x9, 7b            # in ID while EX holds the division, then taken
    ori   x17, x17, 0x08
9:

    # Backward branch on the wrong path, right after a taken branch.
    beq   x0, x0, 1f
    beq   x0, x0, fail          # backward: guessed taken, but never runs
1:

    # Branches back to back: a backward branch at the target of a forward taken branch.
    j     11f
10:
    addi  x13, x13, 1           # target of the backward branch
    j     12f
11:
    beq   x0, x0, 1f
    ori   x17, x17, 0x10
1:
    beq   x0, x0, 10b
    ori   x17, x17, 0x20
12:

    # Taken branches to addresses not divisible by 4: misaligned fetch traps.
mis_fwd:
    beq   x0, x0, mis_fwd + 6
mis_bwd:
    beq   x0, x0, mis_bwd - 2

    ebreak

    .word (expect_end - expect) / 8
expect:
    EXPECT_REG 5, 0
    EXPECT_REG 6, 10
    EXPECT_REG 10, 0x3
    EXPECT_REG 11, 1
    EXPECT_REG 12, 1
    EXPECT_REG 13, 1
    EXPECT_REG 17, 0
    EXPECT_REG 24, 0 + 4                # mepc - mis_fwd: the forward and the backward branch
    EXPECT_REG 26, 14
    EXPECT_REG 28, 2
    EXPECT_REG 29, 6 - 2                # mtval - mepc: their offsets
expect_end:

    # Traps: only misaligned fetch is expected; continue after the branch.
handler:
    addi  x28, x28, 1
    csrr  x31, mcause
    bnez  x31, fail
    csrr  x31, mtval
    csrr  x27, mepc
    sub   x31, x31, x27
    add   x29, x29, x31
    la    x31, mis_fwd
    sub   x31, x27, x31
    add   x24, x24, x31
    addi  x31, x27, 4
    csrw  mepc, x31
    mret

    .data
    .align 2
one:
    .word 1

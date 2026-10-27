/* Program for TbMig2 with +expect_trap +expect_regs: jumps and conditional branches that a
 * BTB (branch target buffer, in IF) learns, in the corners of the pipeline. Every case runs
 * several times, so that the BTB has an entry from the second time on.
 *
 * - A loop branch, in rounds: taken, then the exit (a hit predicted taken, not taken).
 * - A call (JAL) and a jump (JAL x0) in a loop.
 * - A forward branch taken every time (the static guess says not taken), and one taken
 *   every other time: hits predicted either way, right and wrong.
 * - Two branches 64 bytes apart, in turn: the same entry of a 16-entry BTB, each evicts
 *   the other.
 * - A predicted branch that waits in ID for load data, and one behind a division: fetch
 *   holds at the target meanwhile.
 * - Predicted branches back to back: a branch at the target of a predicted branch.
 * - A loop of two instructions: its branch comes again before its update.
 * - A predicted branch on the wrong path: right after a branch that goes the other way.
 * - A branch to an address not divisible by 4, taken twice, then not taken: it traps when
 *   taken and must not get an entry (else the third time IF would follow it: two bubbles
 *   more); the handler adds up mtval - mepc and continues after the branch.
 * Instructions that must not retire set bits in x17 (expect 0); every case counts its
 * rounds in a register of its own. Anything unexpected ends at `fail`, an EBREAK without a
 * register table: the run fails. After the halting EBREAK: number of expected registers,
 * then pairs register, value.
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
    addi  x6, x0, 0
    addi  x11, x0, 0
    addi  x12, x0, 0
    addi  x13, x0, 0
    addi  x14, x0, 0
    addi  x15, x0, 0
    addi  x16, x0, 0
    addi  x17, x0, 0
    addi  x18, x0, 0
    addi  x19, x0, 0
    addi  x23, x0, 0
    addi  x28, x0, 0            # traps
    addi  x29, x0, 0            # sum of mtval - mepc of the traps

    # Loop branch: 3 rounds of a loop of 5.
    addi  x20, x0, 3
1:
    addi  x5, x0, 5
2:
    addi  x6, x6, 1
    addi  x5, x5, -1
    bnez  x5, 2b
    addi  x20, x20, -1
    bnez  x20, 1b

    # A call and a jump in a loop.
    addi  x20, x0, 4
1:
    jal   x1, func              # x11 += 1
    j     2f
    ori   x17, x17, 0x01
2:
    addi  x20, x20, -1
    bnez  x20, 1b

    # A forward branch taken every time.
    addi  x20, x0, 4
1:
    beq   x0, x0, 2f
    ori   x17, x17, 0x02
2:
    addi  x12, x12, 1
    addi  x20, x20, -1
    bnez  x20, 1b

    # A forward branch taken every other time (rounds 1, 3, 5).
    addi  x20, x0, 6
    addi  x21, x0, 0
1:
    xori  x21, x21, 1
    bnez  x21, 2f
    addi  x13, x13, 1           # rounds 2, 4, 6
2:
    addi  x20, x20, -1
    bnez  x20, 1b

    # Two branches 64 bytes apart, in turn.
    addi  x20, x0, 4
    .balign 64
alias_a:
    beq   x0, x0, 1f
    ori   x17, x17, 0x04
1:
    addi  x14, x14, 1
    j     alias_b
    .balign 64
alias_b:
    beq   x0, x0, 1f
    ori   x17, x17, 0x08
1:
    addi  x15, x15, 1
    addi  x20, x20, -1
    bnez  x20, alias_a

    # A predicted branch that waits in ID for load data.
    la    x8, one
    addi  x20, x0, 4
1:
    lw    x7, 0(x8)
    bnez  x7, 2f                # load-use: one cycle in ID
    ori   x17, x17, 0x10
2:
    addi  x16, x16, 1
    addi  x20, x20, -1
    bnez  x20, 1b

    # A predicted branch behind a division.
    li    x8, 100
    li    x9, 7
    addi  x20, x0, 3
1:
    div   x26, x8, x9
    blt   x0, x9, 2f            # in ID while EX holds the division
    ori   x17, x17, 0x20
2:
    addi  x18, x18, 1
    addi  x20, x20, -1
    bnez  x20, 1b

    # Predicted branches back to back.
    addi  x20, x0, 4
1:
    beq   x0, x0, 2f
    ori   x17, x17, 0x40
2:
    beq   x0, x0, 3f            # at the target of a predicted branch
    ori   x17, x17, 0x80
3:
    addi  x19, x19, 1
    addi  x20, x20, -1
    bnez  x20, 1b

    # A loop of two instructions.
    addi  x5, x0, 8
1:
    addi  x5, x5, -1
    bnez  x5, 1b

    # A predicted branch on the wrong path: B right after A, which is taken every other
    # round; B runs (taken) only in the rounds A is not taken.
    addi  x20, x0, 6
    addi  x21, x0, 0
1:
    xori  x21, x21, 1
    beqz  x21, 3f               # A: taken in rounds 2, 4, 6
    beq   x0, x0, 2f            # B
    ori   x17, x17, 0x100
2:
    addi  x23, x23, 1           # rounds 1, 3, 5
3:
    addi  x20, x20, -1
    bnez  x20, 1b

    # A branch to an address not divisible by 4, taken twice (misaligned fetch traps),
    # then not taken.
    addi  x20, x0, 3
    addi  x21, x0, 2
mis:
    bge   x20, x21, mis + 6
    addi  x20, x20, -1
    bnez  x20, mis

    ebreak

    .word (expect_end - expect) / 8
expect:
    EXPECT_REG 5, 0
    EXPECT_REG 6, 15
    EXPECT_REG 11, 4
    EXPECT_REG 12, 4
    EXPECT_REG 13, 3
    EXPECT_REG 14, 4
    EXPECT_REG 15, 4
    EXPECT_REG 16, 4
    EXPECT_REG 17, 0
    EXPECT_REG 18, 3
    EXPECT_REG 19, 4
    EXPECT_REG 20, 0
    EXPECT_REG 23, 3
    EXPECT_REG 26, 14
    EXPECT_REG 28, 2
    EXPECT_REG 29, 6 + 6                # mtval - mepc: the offset of the branch, twice
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
    addi  x31, x27, 4
    csrw  mepc, x31
    mret

func:
    addi  x11, x11, 1
    ret

    .data
    .align 2
one:
    .word 1

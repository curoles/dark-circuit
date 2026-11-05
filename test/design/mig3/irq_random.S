/* Program for TbMig3 with +irq_random +expect_trap +expect_regs: interrupts at random
 * places must not change what a program computes (precise interrupts).
 *
 * work computes a checksum: a pseudo-random sequence (mul) indexes an array (loads,
 * stores), divides (divu), calls a leaf function on some values (data-dependent branches,
 * calls and returns) and counts with an LR/SC loop. It runs twice: with MIE = 0 (no
 * interrupt), then with MIE = 1, while the interrupt source of the testbench raises meip
 * at random times (+irq_random, +irq_max_gap). The handler checks mcause into s6, counts in
 * s7, claims (a store to irq_claim) and returns with MIE = 1 again. An interrupt can land
 * on any instruction: an SC (it fails, the loop tries again), a division in its first
 * cycle, a call (the return-address stack is pushed again: one return guessed wrong, no
 * error), a store that the D-cache does not take at once. Expected: the same checksum
 * (s3 = 0), at least one interrupt (s4 = 1), mcause right every time (s6 = 0).
 */
    .macro EXPECT_REG r, value
    .word \r, \value
    .endm

    .section .text.start, "ax"
    .globl _start
_start:
    la    t0, handler
    csrw  mtvec, t0
    li    t0, 0x800
    csrs  mie, t0                   # MEIE = 1; MIE is 0 after reset
    la    s0, counter
    li    s5, 1103515245            # multiplier of the sequence
    li    s6, 0
    li    s7, 0
    jal   s9, work                  # MIE = 0
    mv    s1, a0
    csrsi mstatus, 8                # MIE = 1
    jal   s9, work
    csrci mstatus, 8
    mv    s2, a0
    sub   s3, s1, s2
    snez  s4, s7
    ebreak

    .word (expect_end - expect) / 8
expect:
    EXPECT_REG 19, 0                # s3
    EXPECT_REG 20, 1                # s4
    EXPECT_REG 22, 0                # s6
expect_end:

    /* Checksum into a0; returns with jr s9. Uses t0-t6, a0-a4, ra. */
work:
    la    t0, arr
    li    t1, 64
1:  sw    zero, 0(t0)               # every run starts from the same memory
    addi  t0, t0, 4
    addi  t1, t1, -1
    bnez  t1, 1b
    sw    zero, 0(s0)
    la    t0, arr
    li    t1, 64
    li    a0, 0
    li    t2, 12345
2:  mul   t2, t2, s5
    addi  t2, t2, 1013
    srli  t3, t2, 22
    andi  t3, t3, 0xfc
    add   t4, t0, t3
    lw    t5, 0(t4)
    add   t5, t5, t2
    sw    t5, 0(t4)
    andi  t6, t2, 0xff
    addi  t6, t6, 1
    divu  a1, t5, t6
    add   a0, a0, a1
    andi  a2, t2, 0x100
    beqz  a2, 3f
    call  leaf
3:  lr.w  a3, (s0)
    addi  a3, a3, 1
    sc.w  a4, a3, (s0)
    bnez  a4, 3b
    add   a0, a0, a3
    addi  t1, t1, -1
    bnez  t1, 2b
    jr    s9

leaf:
    addi  a0, a0, 3
    ret

handler:
    csrr  a6, mcause
    li    a7, 0x8000000b
    xor   a6, a6, a7
    or    s6, s6, a6
    addi  s7, s7, 1
    la    a6, irq_claim
    sw    zero, 0(a6)               # claim: the source drops meip
    mret                            # MPIE = 1: MIE = 1 again

    .data
    .balign 4
counter:
    .word 0
irq_claim:
    .word 0
    .balign 64
arr:
    .space 256

/* Program for TbMig3 with +irq_random +expect_trap +expect_regs: the machine external
 * interrupt (meip) taken on chosen instructions.
 *
 * The interrupt source of the testbench (TbMig3Irq) raises meip at random times and drops
 * it when the handler claims, with a store to irq_claim. The program places every interrupt
 * exactly, without counting cycles: with MIE = 0 it waits until mip.MEIP is 1 (ARM), then
 * sets MIE; the spec takes the interrupt right after that CSR write, so on the next
 * instruction, c<n>. The handler checks mcause (0x8000000b), mtval (0), mstatus (MIE 0,
 * MPIE 1) into s6, counts in s7, keeps mepc in s8 (the one before in s9), claims, and
 * clears MPIE, so MRET returns with MIE = 0. CHECK c<n>: mepc was c<n> (errors into s6).
 *  1. MIE = 0 masks: meip is 1, nothing is taken (s1 = 0).
 *  2. MEIE = 0 masks, also with MIE = 1 (s2 = 0); setting MEIE takes it on the next
 *     instruction, which then runs once (s3 = 1).
 *  3. On a store, 4. a load (a0 = 0x55), 5. a division (a1 = 14): each runs once, after
 *     MRET.
 *  6. On an SC after an LR: the trap ends the reservation, the SC fails (a2 = 1).
 *  7. On a CSR write: it is done after MRET (a3 = 0x1234).
 *  8. On a jump: it jumps after MRET (a4 stays 0).
 *  9. The handler does not claim (s10 = 1): MRET leaves MIE 1 and meip is still 1, so the
 *     interrupt is taken again on the same instruction (s9 = s8 = c9), which then runs once
 *     (a5 = 1).
 * 10. On the halting EBREAK: it halts after MRET (s8 = c10, s7 = 10 interrupts, s6 = 0).
 */
    .macro EXPECT_REG r, value
    .word \r, \value
    .endm

    /* Wait until meip is pending (mip.MEIP, bit 11), then set MIE (mstatus bit 3): the
       interrupt is taken on the instruction after the macro. */
    .macro ARM
1:  csrr  t0, mip
    srli  t0, t0, 11
    andi  t0, t0, 1
    beqz  t0, 1b
    csrsi mstatus, 8
    .endm

    /* mepc of the last interrupt was \label. */
    .macro CHECK label
    la    t1, \label
    sub   t1, s8, t1
    or    s6, s6, t1
    .endm

    .section .text.start, "ax"
    .globl _start
_start:
    la    t0, handler
    csrw  mtvec, t0
    la    s0, data
    li    s3, 0
    li    s6, 0
    li    s7, 0
    li    s8, 0
    li    s10, 0
    li    a4, 0
    li    a5, 0
    li    t0, 0x800
    csrs  mie, t0                   # MEIE = 1; MIE is 0 after reset

    # 1. MIE = 0 masks.
1:  csrr  t0, mip
    srli  t0, t0, 11
    andi  t0, t0, 1
    beqz  t0, 1b
    nop
    nop
    nop
    mv    s1, s7

    # 2. MEIE = 0 masks; setting MEIE takes it at once.
    li    t0, 0x800
    csrc  mie, t0
    csrsi mstatus, 8
    nop
    nop
    mv    s2, s7
    csrs  mie, t0
c2: addi  s3, s3, 1
    CHECK c2

    # 3. A store.
    li    t2, 0x55
    ARM
c3: sw    t2, 0(s0)
    CHECK c3

    # 4. A load.
    ARM
c4: lw    a0, 0(s0)
    CHECK c4

    # 5. A division.
    li    t3, 100
    li    t4, 7
    ARM
c5: div   a1, t3, t4
    CHECK c5

    # 6. An SC after an LR.
    lr.w  t5, (s0)
    ARM
c6: sc.w  a2, t2, (s0)
    CHECK c6

    # 7. A CSR write.
    li    t6, 0x1234
    ARM
c7: csrw  mscratch, t6
    csrr  a3, mscratch
    CHECK c7

    # 8. A jump.
    ARM
c8: j     2f
    li    a4, 1
2:  CHECK c8

    # 9. No claim: taken twice on the same instruction.
    li    s10, 1
    ARM
c9: addi  a5, a5, 1
    CHECK c9
    sub   t1, s9, s8
    or    s6, s6, t1

    # 10. The halting EBREAK.
    ARM
c10:
    ebreak

    .word (expect_end - expect) / 8
expect:
    EXPECT_REG 9,  0                # s1
    EXPECT_REG 18, 0                # s2
    EXPECT_REG 19, 1                # s3
    EXPECT_REG 10, 0x55             # a0
    EXPECT_REG 11, 14               # a1
    EXPECT_REG 12, 1                # a2
    EXPECT_REG 13, 0x1234           # a3
    EXPECT_REG 14, 0                # a4
    EXPECT_REG 15, 1                # a5
    EXPECT_REG 22, 0                # s6
    EXPECT_REG 23, 10               # s7
    EXPECT_REG 24, c10              # s8
expect_end:

handler:
    csrr  a6, mcause
    li    a7, 0x8000000b
    xor   a6, a6, a7
    or    s6, s6, a6
    csrr  a6, mtval
    or    s6, s6, a6
    csrr  a6, mstatus
    andi  a6, a6, 0x88              # MPIE, MIE
    xori  a6, a6, 0x80              # 0 when MPIE = 1 and MIE = 0
    or    s6, s6, a6
    addi  s7, s7, 1
    mv    s9, s8
    csrr  s8, mepc
    bnez  s10, 3f
    la    a6, irq_claim
    sw    zero, 0(a6)               # claim: the source drops meip
    li    a6, 0x80
    csrc  mstatus, a6               # MPIE = 0: MRET leaves MIE 0
    mret
3:  li    s10, 0                    # no claim: MPIE stays 1, meip stays 1
    mret

    .data
    .balign 4
data:
    .word 0
irq_claim:
    .word 0

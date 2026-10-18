/* Program for TbMig1 with +expect_regs: CSR instructions (Zicsr) and counters (Zicntr).
 *
 * - mscratch with all six operations; rd gets the old value.
 * - Read-only CSRs (misa, mhartid, mvendorid) read with csrr (csrrs rs1=x0, no write).
 * - instret: two reads 3 instructions apart differ by 4 (the first read counts too).
 * - cycle: two reads 3 instructions apart differ by 3 (one cycle per instruction here);
 *   time reads the same counter as cycle.
 * - Writes of minstret, mcycle, mcycleh: the next read gives the written value (the
 *   write wins over the count of its cycle).
 * After the halting EBREAK: number of expected registers, then pairs register, value.
 */
    .macro EXPECT_REG r, value
    .word \r, \value
    .endm

    .section .text.start, "ax"
    .globl _start
_start:
    li     x1, 0x12345678
    csrrw  x2, mscratch, x1         # x2 = 0 (reset), mscratch = 0x12345678
    li     x3, 0x0000ff00
    csrrs  x4, mscratch, x3         # mscratch |= 0x0000ff00
    li     x5, 0x00f0000f
    csrrc  x6, mscratch, x5         # mscratch &= ~0x00f0000f
    csrrwi x7, mscratch, 21         # mscratch = 21
    csrrsi x8, mscratch, 10         # mscratch = 21 | 10 = 31
    csrrci x9, mscratch, 3          # mscratch = 31 & ~3 = 28
    csrr   x10, mscratch

    csrr   x11, misa
    csrr   x12, mhartid
    csrr   x13, mvendorid

    rdinstret x14
    nop
    nop
    nop
    rdinstret x15
    sub    x16, x15, x14

    rdcycle x17
    nop
    nop
    rdcycle x18
    sub    x19, x18, x17
    rdtime  x20
    rdcycle x21
    sub    x22, x21, x20

    li     x23, 1000
    csrw   minstret, x23
    rdinstret x24
    csrw   mcycle, x23
    rdcycle x25
    li     x26, 7
    csrw   mcycleh, x26
    rdcycleh x27

    ebreak

    .word (expect_end - expect) / 8
expect:
    EXPECT_REG 2,  0
    EXPECT_REG 4,  0x12345678
    EXPECT_REG 6,  0x12345678 | 0x0000ff00
    EXPECT_REG 7,  (0x12345678 | 0x0000ff00) & ~0x00f0000f
    EXPECT_REG 8,  21
    EXPECT_REG 9,  21 | 10
    EXPECT_REG 10, (21 | 10) & ~3
    EXPECT_REG 11, 0x40000100       # misa: MXL=1 (32-bit), extension I
    EXPECT_REG 12, 0
    EXPECT_REG 13, 0
    EXPECT_REG 16, 4
    EXPECT_REG 19, 3
    EXPECT_REG 22, 1
    EXPECT_REG 24, 1000
    EXPECT_REG 25, 1000
    EXPECT_REG 27, 7
expect_end:

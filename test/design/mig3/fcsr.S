/* Program for TbMig3 with +expect_regs: the floating-point CSRs of Zfinx, fcsr = {frm,
 * fflags} with frm and fflags as views of its fields (assembled with Zfinx: the CSR names
 * and the frcsr/fscsr pseudo-instructions need it).
 *
 * - fscsr of all ones: fcsr reads 0xff (bits 31..8 are 0), frm 7, fflags 0x1f; the swap
 *   returns the old fcsr (0 after reset).
 * - frm and fflags written alone (fsrmi, fsflagsi): fcsr reads both fields; the swaps return
 *   the old field.
 * - Set and clear on fflags and frm change only their bits.
 * - fscsr of 0x123: the bits above 7 are dropped.
 * After the halting EBREAK: number of expected registers, then pairs register, value.
 */
    .macro EXPECT_REG r, value
    .word \r, \value
    .endm

    .section .text.start, "ax"
    .globl _start
_start:
    li       x1, -1
    fscsr    x2, x1                 # x2 = 0 (reset), fcsr = 0xff
    frcsr    x3                     # 0xff
    frrm     x4                     # 7
    frflags  x5                     # 0x1f
    fsrmi    x6, 2                  # x6 = 7, frm = 2 (RDN)
    fsflagsi x7, 0x05               # x7 = 0x1f, fflags = OF | NX = 0x05
    frcsr    x8                     # (2 << 5) | 0x05 = 0x45
    csrrsi   x9, fflags, 0x0a       # x9 = 0x05, fflags = 0x0f
    csrrci   x10, fflags, 0x03      # x10 = 0x0f, fflags = 0x0c
    csrrsi   x11, frm, 1            # x11 = 2, frm = 3
    frcsr    x12                    # (3 << 5) | 0x0c = 0x6c
    li       x13, 0x123
    fscsr    x14, x13               # x14 = 0x6c, fcsr = 0x23 (frm 1, fflags 3)
    frcsr    x15                    # 0x23
    frrm     x16                    # 1
    frflags  x17                    # 3
    ebreak

    .word (expect_end - expect) / 8
expect:
    EXPECT_REG 2,  0
    EXPECT_REG 3,  0xff
    EXPECT_REG 4,  7
    EXPECT_REG 5,  0x1f
    EXPECT_REG 6,  7
    EXPECT_REG 7,  0x1f
    EXPECT_REG 8,  0x45
    EXPECT_REG 9,  0x05
    EXPECT_REG 10, 0x0f
    EXPECT_REG 11, 2
    EXPECT_REG 12, 0x6c
    EXPECT_REG 14, 0x6c
    EXPECT_REG 15, 0x23
    EXPECT_REG 16, 1
    EXPECT_REG 17, 3
expect_end:

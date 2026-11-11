/* Program for TbMig3 with +expect_regs: the fused forms of Zfinx (FMADD.S, FMSUB.S,
 * FNMSUB.S, FNMADD.S), whose rs3 Mig3Fpu reads in the first EX cycle through ID's rs2 port
 * (assembled with Zfinx).
 *
 * - One rounding: a = 1 + 2^-12, a * a = 1 + 2^-11 + 2^-24 exactly; with -(1 + 2^-11) added
 *   the result is 2^-24 (0x33800000). Rounding the product first would give 1 + 2^-11 (a
 *   tie to even) and then 0. Each form, the signs flipped so that every one gives +-2^-24.
 * - rs3 the result of the instruction right before (in MEM/WB when the R4 reads rs3),
 *   rs3 loaded right before (a D-cache hit, and a miss: its word comes in MEM/WB, the R4
 *   waits in EX until then, no interlock in ID),
 *   rs1 = rs2 = rs3, rs3 the result of the R4 right before, rs3 = rd (forwarding from EX,
 *   which holds the R4 itself, is off while it reads rs3: the value of the li right before).
 * - All exact: fflags 0.
 * After the halting EBREAK: number of expected registers, then pairs register, value.
 */
    .macro EXPECT_REG r, value
    .word \r, \value
    .endm

    .section .text.start, "ax"
    .globl _start
_start:
    li        x1, 0x3f800800        # a = 1 + 2^-12
    li        x2, 0x3f801000        # 1 + 2^-11
    li        x3, 0xbf801000        # -(1 + 2^-11)
    li        x4, 0x40000000        # 2.0
    la        x6, cneg
    lw        x8, 0(x6)             # cneg's line into the D-cache: the load below hits
    fmadd.s   x10, x1, x1, x3       # a*a - (1 + 2^-11) = 2^-24
    fmsub.s   x11, x1, x1, x2       # a*a - (1 + 2^-11) = 2^-24
    fnmsub.s  x12, x1, x1, x2       # -(a*a) + (1 + 2^-11) = -2^-24
    fnmadd.s  x13, x1, x1, x3       # -(a*a) - (-(1 + 2^-11)) = -2^-24
    fadd.s    x5, x2, x0            # 1 + 2^-11 (+0 added)
    fmsub.s   x14, x1, x1, x5       # rs3 the result right before: 2^-24
    lw        x7, 0(x6)             # -(1 + 2^-11), a hit
    fmadd.s   x15, x1, x1, x7       # rs3 loaded right before: 2^-24
    la        x21, cfar
    lw        x20, 0(x21)           # -(1 + 2^-11), a miss: the R4 waits behind it in EX
    fmadd.s   x22, x1, x1, x20      # rs3 loaded right before, a miss: 2^-24
    fmadd.s   x16, x4, x4, x4       # 2 * 2 + 2 = 6.0
    fmadd.s   x17, x16, x4, x16     # rs3 the R4 result right before: 6 * 2 + 6 = 18.0
    li        x19, 0x40000000       # 2.0
    fmadd.s   x19, x4, x4, x19      # rs3 = rd: 2 * 2 + 2 = 6.0
    frflags   x18                   # 0
    ebreak

    .word (expect_end - expect) / 8
expect:
    EXPECT_REG 5,  0x3f801000
    EXPECT_REG 7,  0xbf801000
    EXPECT_REG 8,  0xbf801000
    EXPECT_REG 10, 0x33800000
    EXPECT_REG 11, 0x33800000
    EXPECT_REG 12, 0xb3800000
    EXPECT_REG 13, 0xb3800000
    EXPECT_REG 14, 0x33800000
    EXPECT_REG 15, 0x33800000
    EXPECT_REG 16, 0x40c00000
    EXPECT_REG 17, 0x41900000
    EXPECT_REG 18, 0
    EXPECT_REG 19, 0x40c00000
    EXPECT_REG 20, 0xbf801000
    EXPECT_REG 22, 0x33800000
expect_end:

    .data
    .balign 4
cneg:
    .word 0xbf801000
    .balign 64
cfar:                               # a line nothing else touches: a D-cache miss
    .word 0xbf801000

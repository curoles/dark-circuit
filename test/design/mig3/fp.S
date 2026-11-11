/* Program for TbMig3 with +expect_regs: F instructions on the x registers (Zfinx), one or more
 * of every unit of Mig3Fpu, the rounding modes and the flags (assembled with Zfinx).
 *
 * - FADD.S, FSUB.S, FMUL.S back to back, FMUL.S reading the two results before it at once
 *   (forwarded from EX and MEM/WB), FDIV.S (inexact), FSQRT.S, FMIN.S, FMAX.S, FEQ.S, FLT.S,
 *   FLE.S, FSGNJN.S, FSGNJX.S, FCLASS.S, FCVT.W.S, FCVT.WU.S, FCVT.S.W, FCVT.S.WU (inexact):
 *   fflags then NX only.
 * - Rounding: 1/3 toward zero (rm field), down (frm, rm DYN), -1/3 up (frm); 2.5 to an
 *   integer to nearest, ties away (3) and ties to even (2); fflags NX.
 * - Flags: 1/0 is +inf with DZ, sqrt(-2) the default NaN with NV, 2^127 * 2^127 +inf with OF
 *   and NX: fflags 0x1d.
 * Expected values: the double result rounded to float32 to nearest (the same as rounding the
 * exact result, for + - * / and sqrt of float32 operands), the directed modes the float32
 * neighbour on their side.
 * After the halting EBREAK: number of expected registers, then pairs register, value.
 */
    .macro EXPECT_REG r, value
    .word \r, \value
    .endm

    .section .text.start, "ax"
    .globl _start
_start:
    li        x1, 0x3f800000        # 1.0
    li        x2, 0x40400000        # 3.0
    fadd.s    x3, x1, x2            # 4.0
    fsub.s    x4, x1, x2            # -2.0
    fmul.s    x5, x3, x4            # -8.0
    fdiv.s    x6, x1, x2            # 1/3, NX
    fsqrt.s   x7, x3                # 2.0
    fmin.s    x8, x4, x1            # -2.0
    fmax.s    x9, x4, x1            # 1.0
    feq.s     x10, x1, x1           # 1
    flt.s     x11, x4, x1           # 1
    fle.s     x12, x1, x4           # 0
    fsgnjn.s  x13, x1, x1           # -1.0
    fsgnjx.s  x14, x2, x4           # -3.0
    fclass.s  x15, x4               # negative normal: bit 1
    fcvt.w.s  x16, x5               # -8
    fcvt.wu.s x17, x3               # 4
    li        x18, -5
    fcvt.s.w  x19, x18              # -5.0
    fcvt.s.wu x20, x18              # 4294967291 -> 2^32, NX
    frflags   x21                   # NX

    fsflagsi  0
    fdiv.s    x22, x1, x2, rtz      # 1/3 toward zero
    fsrmi     2                     # frm = RDN
    fdiv.s    x23, x1, x2           # 1/3 down (DYN)
    fsrmi     3                     # frm = RUP
    fdiv.s    x24, x13, x2          # -1/3 up (DYN)
    li        x25, 0x40200000       # 2.5
    fcvt.w.s  x26, x25, rmm         # 3
    fcvt.w.s  x27, x25, rne         # 2
    frflags   x28                   # NX

    fsflagsi  0
    fdiv.s    x29, x1, x0           # 1/+0 = +inf, DZ
    fsqrt.s   x30, x4               # sqrt(-2): the default NaN, NV
    li        x31, 0x7f000000       # 2^127
    fmul.s    x31, x31, x31         # +inf, OF NX
    frflags   x18                   # NV DZ OF NX
    ebreak

    .word (expect_end - expect) / 8
expect:
    EXPECT_REG 3,  0x40800000
    EXPECT_REG 4,  0xc0000000
    EXPECT_REG 5,  0xc1000000
    EXPECT_REG 6,  0x3eaaaaab
    EXPECT_REG 7,  0x40000000
    EXPECT_REG 8,  0xc0000000
    EXPECT_REG 9,  0x3f800000
    EXPECT_REG 10, 1
    EXPECT_REG 11, 1
    EXPECT_REG 12, 0
    EXPECT_REG 13, 0xbf800000
    EXPECT_REG 14, 0xc0400000
    EXPECT_REG 15, 0x2
    EXPECT_REG 16, 0xfffffff8
    EXPECT_REG 17, 4
    EXPECT_REG 18, 0x1d
    EXPECT_REG 19, 0xc0a00000
    EXPECT_REG 20, 0x4f800000
    EXPECT_REG 21, 0x01
    EXPECT_REG 22, 0x3eaaaaaa
    EXPECT_REG 23, 0x3eaaaaaa
    EXPECT_REG 24, 0xbeaaaaaa
    EXPECT_REG 26, 3
    EXPECT_REG 27, 2
    EXPECT_REG 28, 0x01
    EXPECT_REG 29, 0x7f800000
    EXPECT_REG 30, 0x7fc00000
    EXPECT_REG 31, 0x7f800000
expect_end:

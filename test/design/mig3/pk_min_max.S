/* Program for TbMig3 with +expect_regs: Mig3's packed minimum and maximum (P extension,
 * draft; assembled with clang's experimental P): PMIN, PMINU, PMAX, PMAXU, .B and .H.
 *
 * The operands make every result differ: as bytes and as halfwords, signed and unsigned
 * (0x0100 > 0x00ff as halfwords, while byte 01 > 00 and byte 00 < ff unsigned but > ff
 * signed). Equal lanes; a ReLU (the maximum with 0) used at once by a clamp (the minimum
 * with a limit), forwarded from EX; no vxsat (a - b overflows in some lanes, but these
 * instructions do not saturate).
 * After the halting EBREAK: number of expected registers, then pairs register, value.
 */
    .macro EXPECT_REG r, value
    .word \r, \value
    .endm

    .section .text.start, "ax"
    .globl _start
_start:
    li       x1, 0x01007f80         # bytes 01 00 7f 80, halfwords 0100 7f80
    li       x2, 0x00ff80ff         # bytes 00 ff 80 ff, halfwords 00ff 80ff
    pmin.b   x3, x1, x2             # 00 ff 80 80
    pmax.b   x4, x1, x2             # 01 00 7f ff
    pminu.b  x5, x1, x2             # 00 00 7f 80
    pmaxu.b  x6, x1, x2             # 01 ff 80 ff
    pmin.h   x7, x1, x2             # 00ff 80ff (256 > 255; 32640 > -32513)
    pmax.h   x8, x1, x2             # 0100 7f80
    pminu.h  x9, x1, x2             # 00ff 7f80 (32640 < 33023)
    pmaxu.h  x10, x1, x2            # 0100 80ff
    pmin.b   x11, x2, x2            # equal lanes: x2
    pmax.b   x12, x2, x0            # ReLU: 00 00 00 00 (00 stays, ff 80 ff are negative)
    pmax.b   x13, x1, x0            # ReLU: 01 00 7f 00
    lui      x14, 0x40404           # 0x40404040: the limit 64 in every byte (not li:
    addi     x14, x14, 0x040        # with P the assembler may make it PLI.B)
    pmin.b   x15, x13, x14          # clamp: 01 00 40 00
    csrr     x16, vxsat             # 0
    ebreak

    .word (expect_end - expect) / 8
expect:
    EXPECT_REG 3,  0x00ff8080
    EXPECT_REG 4,  0x01007fff
    EXPECT_REG 5,  0x00007f80
    EXPECT_REG 6,  0x01ff80ff
    EXPECT_REG 7,  0x00ff80ff
    EXPECT_REG 8,  0x01007f80
    EXPECT_REG 9,  0x00ff7f80
    EXPECT_REG 10, 0x010080ff
    EXPECT_REG 11, 0x00ff80ff
    EXPECT_REG 12, 0x00000000
    EXPECT_REG 13, 0x01007f00
    EXPECT_REG 15, 0x01004000
    EXPECT_REG 16, 0
expect_end:

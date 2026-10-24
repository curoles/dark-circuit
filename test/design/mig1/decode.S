/* Test cases of Mig1Decode, read by TbMig1Decode (never executed).
 *
 * Word 0 is the number of cases. Every case is 11 words: the instruction, encoded
 * by the assembler, then the expected decode: kind, rd_we, uses_rs1, uses_rs2,
 * rd, rs1, rs2, funct3, alt, imm. The assembler is the oracle of the encodings,
 * the macro arguments are what we asked it to encode.
 *
 * How the macros work (GNU assembler):
 * - `.macro NAME a, b` ... `.endm` defines a macro; inside, `\a` is replaced by the
 *   text of argument a. So `OP add, 0, 0, 1, 2, 3` expands to the instruction line
 *   `add x1, x2, x3` (`x\rd` becomes `x1`), followed by
 *   `EXPECT K_OP, 1, 1, 1, 1, 2, 3, 0, 0, 0`.
 * - EXPECT puts the 10 expected values as .word data right after the instruction.
 * - Arguments may be expressions that the assembler computes:
 *   `(\alt << 10) | \shamt` is the expected immediate of a shift, because srai keeps
 *   bit 30 of the instruction (funct7) in imm[10]; `\imm20 << 12` is the value of lui.
 * - `.` is the address of the current line, so `beq x1, x2, . + (-4096)` jumps 4096
 *   bytes back from the branch itself: its immediate is exactly -4096.
 *   `.option norelax` keeps the assembler and linker from changing such code.
 * - `.equ NAME, value` defines a constant, here K_* for the kind numbers.
 * - `(cases_end - cases) / 44` is the number of cases: labels are addresses and
 *   every case is 11 words = 44 bytes.
 */
    .option norelax

/* Kinds, same order as kind_e in rtl/design/mig1/mig1_pkg.sv. */
    .equ K_ILLEGAL, 0
    .equ K_LUI,     1
    .equ K_AUIPC,   2
    .equ K_JAL,     3
    .equ K_JALR,    4
    .equ K_BRANCH,  5
    .equ K_LOAD,    6
    .equ K_STORE,   7
    .equ K_OP_IMM,  8
    .equ K_OP,      9
    .equ K_FENCE,   10
    .equ K_ECALL,   11
    .equ K_EBREAK,  12
    .equ K_CSR,     13
    .equ K_MRET,    14
    .equ K_WFI,     15
    .equ K_MULDIV,  16

/* Expected decode after the instruction. */
    .macro EXPECT kind, rd_we, uses_rs1, uses_rs2, rd, rs1, rs2, funct3, alt, imm
    .word \kind, \rd_we, \uses_rs1, \uses_rs2, \rd, \rs1, \rs2, \funct3, \alt, \imm
    .endm

/* One macro per instruction shape: the instruction, then EXPECT. */
    .macro OP op, funct3, alt, rd, rs1, rs2         /* add sub sll slt sltu xor srl sra or and */
    \op x\rd, x\rs1, x\rs2
    EXPECT K_OP, 1, 1, 1, \rd, \rs1, \rs2, \funct3, \alt, 0
    .endm

    .macro OPI op, funct3, rd, rs1, imm             /* addi slti sltiu xori ori andi */
    \op x\rd, x\rs1, \imm
    EXPECT K_OP_IMM, 1, 1, 0, \rd, \rs1, 0, \funct3, 0, \imm
    .endm

    .macro SHIFTI op, funct3, alt, rd, rs1, shamt   /* slli srli srai: imm is {funct7, shamt} */
    \op x\rd, x\rs1, \shamt
    EXPECT K_OP_IMM, 1, 1, 0, \rd, \rs1, 0, \funct3, \alt, (\alt << 10) | \shamt
    .endm

    .macro LOAD op, funct3, rd, rs1, imm            /* lb lh lw lbu lhu */
    \op x\rd, \imm(x\rs1)
    EXPECT K_LOAD, 1, 1, 0, \rd, \rs1, 0, \funct3, 0, \imm
    .endm

    .macro STORE op, funct3, rs2, rs1, imm          /* sb sh sw */
    \op x\rs2, \imm(x\rs1)
    EXPECT K_STORE, 0, 1, 1, 0, \rs1, \rs2, \funct3, 0, \imm
    .endm

    .macro BRANCH op, funct3, rs1, rs2, offset      /* beq bne blt bge bltu bgeu */
    \op x\rs1, x\rs2, . + (\offset)
    EXPECT K_BRANCH, 0, 1, 1, 0, \rs1, \rs2, \funct3, 0, \offset
    .endm

    .macro UPPER op, kind, rd, imm20                /* lui auipc */
    \op x\rd, \imm20
    EXPECT \kind, 1, 0, 0, \rd, 0, 0, 0, 0, \imm20 << 12
    .endm

    .macro JAL_ rd, offset
    jal x\rd, . + (\offset)
    EXPECT K_JAL, 1, 0, 0, \rd, 0, 0, 0, 0, \offset
    .endm

    .macro JALR_ rd, rs1, imm
    jalr x\rd, \imm(x\rs1)
    EXPECT K_JALR, 1, 1, 0, \rd, \rs1, 0, 0, 0, \imm
    .endm

    .macro MULDIV op, funct3, rd, rs1, rs2          /* mul mulh mulhsu mulhu div divu rem remu */
    \op x\rd, x\rs1, x\rs2
    EXPECT K_MULDIV, 1, 1, 1, \rd, \rs1, \rs2, \funct3, 0, 0
    .endm

    .macro CSR op, funct3, rd, rs1, csr             /* csrrw csrrs csrrc: imm is the CSR address */
    \op x\rd, \csr, x\rs1
    EXPECT K_CSR, 1, 1, 0, \rd, \rs1, 0, \funct3, 0, \csr
    .endm

    .macro CSRI op, funct3, rd, zimm, csr           /* csrrwi csrrsi csrrci: the rs1 field is zimm */
    \op x\rd, \csr, \zimm
    EXPECT K_CSR, 1, 0, 0, \rd, 0, 0, \funct3, 0, \csr
    .endm

    .macro NOARG insn, kind                         /* fence ecall ebreak mret wfi */
    \insn
    EXPECT \kind, 0, 0, 0, 0, 0, 0, 0, 0, 0
    .endm

    .macro ILLEGAL word                             /* not an RV32I instruction */
    .word \word
    EXPECT K_ILLEGAL, 0, 0, 0, 0, 0, 0, 0, 0, 0
    .endm

    .section .text.start, "ax"
    .globl _start
_start:
    .word (cases_end - cases) / 44
cases:
    /*     op     funct3 alt  rd  rs1 rs2 */
    OP     add,   0,     0,   1,  2,  3
    OP     sub,   0,     1,   31, 30, 29
    OP     sll,   1,     0,   0,  31, 15
    OP     slt,   2,     0,   15, 0,  31
    OP     sltu,  3,     0,   7,  8,  9
    OP     xor,   4,     0,   3,  1,  2
    OP     srl,   5,     0,   10, 11, 12
    OP     sra,   5,     1,   13, 14, 15
    OP     or,    6,     0,   16, 17, 18
    OP     and,   7,     0,   19, 20, 21

    /*     op     funct3 rd  rs1 imm */
    OPI    addi,  0,     5,  6,  -2048
    OPI    addi,  0,     31, 0,  2047
    OPI    addi,  0,     0,  0,  0
    OPI    slti,  2,     1,  2,  -1
    OPI    sltiu, 3,     1,  1,  -1
    OPI    xori,  4,     3,  4,  -2048
    OPI    ori,   6,     5,  6,  1
    OPI    andi,  7,     7,  8,  2047

    /*     op     funct3 alt  rd  rs1 shamt */
    SHIFTI slli,  1,     0,   2,  3,  0
    SHIFTI slli,  1,     0,   4,  4,  31
    SHIFTI srli,  5,     0,   4,  5,  31
    SHIFTI srai,  5,     1,   11, 11, 12
    SHIFTI srai,  5,     1,   31, 1,  31

    /*     op     funct3 rd  rs1 imm */
    LOAD   lb,    0,     1,  2,  -2048
    LOAD   lh,    1,     3,  4,  0
    LOAD   lw,    2,     5,  6,  2047
    LOAD   lbu,   4,     0,  31, -1
    LOAD   lhu,   5,     31, 31, 2047

    /*     op     funct3 rs2 rs1 imm */
    STORE  sb,    0,     5,  6,  -1
    STORE  sh,    1,     0,  1,  -2048
    STORE  sw,    2,     31, 0,  2047

    /*     op     funct3 rs1 rs2 offset */
    BRANCH beq,   0,     1,  2,  -4096
    BRANCH bne,   1,     3,  4,  2
    BRANCH blt,   4,     5,  6,  -2
    BRANCH bge,   5,     7,  8,  8
    BRANCH bltu,  6,     0,  31, -4
    BRANCH bgeu,  7,     31, 30, 4094

    /*     op     kind     rd  imm20 */
    UPPER  lui,   K_LUI,   4,  0x12345
    UPPER  lui,   K_LUI,   0,  0
    UPPER  auipc, K_AUIPC, 31, 0xfffff
    UPPER  auipc, K_AUIPC, 1,  1

    /*     rd  offset */
    JAL_   1,  -1048576
    JAL_   0,  1048574
    JAL_   31, 4

    /*     rd  rs1 imm */
    JALR_  0,  1,  0
    JALR_  5,  31, -2048
    JALR_  1,  1,  2047

    /*     op      funct3 rd  rs1 rs2 */
    MULDIV mul,    0,     1,  2,  3
    MULDIV mulh,   1,     31, 30, 29
    MULDIV mulhsu, 2,     0,  31, 1
    MULDIV mulhu,  3,     5,  0,  31
    MULDIV div,    4,     7,  8,  9
    MULDIV divu,   5,     10, 11, 0
    MULDIV rem,    6,     12, 13, 14
    MULDIV remu,   7,     15, 16, 17

    /*     op      funct3 rd  rs1 csr: addresses with bit 11 set must not be sign-extended */
    CSR    csrrw,  1,     1,  2,  0x340
    CSR    csrrs,  2,     31, 0,  0xc00
    CSR    csrrc,  3,     0,  31, 0xfff

    /*     op      funct3 rd  zimm csr */
    CSRI   csrrwi, 5,     5,  31,  0x800
    CSRI   csrrsi, 6,     0,  0,   0xb02
    CSRI   csrrci, 7,     17, 1,   0x7ff

    NOARG  fence,  K_FENCE
    NOARG  ecall,  K_ECALL
    NOARG  ebreak, K_EBREAK
    NOARG  mret,   K_MRET
    NOARG  wfi,    K_WFI

    ILLEGAL 0x00000000      /* all zeros: defined to be illegal */
    ILLEGAL 0xffffffff      /* all ones: defined to be illegal */
    ILLEGAL 0xfe000033      /* OP with funct7 = 0x7f: neither OP nor M */
    ILLEGAL 0x0000100f      /* fence.i: Zifencei extension */
    ILLEGAL 0x00200073      /* like ecall and ebreak, but imm=2 */
    ILLEGAL 0x0000000b      /* custom-0 opcode */
cases_end:

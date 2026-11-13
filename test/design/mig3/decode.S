/* Test cases of Mig3Decode, read by TbMig3Decode (never executed).
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

/* Kinds, same order as kind_e in rtl/design/mig3/mig3_pkg.sv. */
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
    .equ K_BITMANIP, 17
    .equ K_LR,      18
    .equ K_SC,      19
    .equ K_AMO,     20
    .equ K_CBO,     21
    .equ K_FP,      22
    .equ K_PACKED,  23
    .equ K_PMUL,    24

/* funct7 of the Zbb rotates ROL, ROR, RORI (0110000); RORI's immediate is {F7_ROT, shamt}. */
    .equ F7_ROT,    0x30

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

    .macro RORI_ rd, rs1, shamt                     /* rori (Zbb): imm is {F7_ROT, shamt} */
    rori x\rd, x\rs1, \shamt
    EXPECT K_OP_IMM, 1, 1, 0, \rd, \rs1, 0, 5, 1, (F7_ROT << 5) | \shamt
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

    .macro BITMANIP op, rd, rs1                     /* sext.b ... rev8 clz ctz cpop (Zbb) */
    \op x\rd, x\rs1
    EXPECT K_BITMANIP, 1, 1, 0, \rd, \rs1, 0, 0, 0, 0
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

    .macro LR_ rd, rs1, ord=                        /* lr.w lr.w.aq ...: rs1, imm 0 */
    lr.w\ord x\rd, (x\rs1)
    EXPECT K_LR, 1, 1, 0, \rd, \rs1, 0, 2, 0, 0
    .endm

    .macro SC_ rd, rs2, rs1, ord=                   /* sc.w sc.w.rl ... */
    sc.w\ord x\rd, x\rs2, (x\rs1)
    EXPECT K_SC, 1, 1, 1, \rd, \rs1, \rs2, 2, 0, 0
    .endm

    .macro AMO_ op, rd, rs2, rs1, ord=              /* amoadd.w ... amomaxu.w: imm 0 */
    \op\ord x\rd, x\rs2, (x\rs1)
    EXPECT K_AMO, 1, 1, 1, \rd, \rs1, \rs2, 2, 0, 0
    .endm

    .macro CBO_ op, rs1                             /* cbo.clean cbo.flush cbo.inval: imm 0 */
    \op (x\rs1)
    EXPECT K_CBO, 0, 1, 0, 0, \rs1, 0, 2, 0, 0
    .endm

/* F on the x registers (Zfinx). funct3 is the rm field (rmv: the value of the name rm)
   or the operation; the imm column holds rs3 of the R4 forms (they have no immediate). */
    .macro FMA4 op, rd, rs1, rs2, rs3, rm, rmv      /* fmadd.s fmsub.s fnmsub.s fnmadd.s */
    \op x\rd, x\rs1, x\rs2, x\rs3, \rm
    EXPECT K_FP, 1, 1, 1, \rd, \rs1, \rs2, \rmv, 0, \rs3
    .endm

    .macro FP2RM op, rd, rs1, rs2, rm, rmv          /* fadd.s fsub.s fmul.s fdiv.s */
    \op x\rd, x\rs1, x\rs2, \rm
    EXPECT K_FP, 1, 1, 1, \rd, \rs1, \rs2, \rmv, 0, 0
    .endm

    .macro FP2 op, f3, rd, rs1, rs2                 /* fsgnj* fmin fmax feq flt fle */
    \op x\rd, x\rs1, x\rs2
    EXPECT K_FP, 1, 1, 1, \rd, \rs1, \rs2, \f3, 0, 0
    .endm

    .macro FP1RM op, rd, rs1, rm, rmv               /* fsqrt.s fcvt.* */
    \op x\rd, x\rs1, \rm
    EXPECT K_FP, 1, 1, 0, \rd, \rs1, 0, \rmv, 0, 0
    .endm

    .macro FP1 op, f3, rd, rs1                      /* fclass.s */
    \op x\rd, x\rs1
    EXPECT K_FP, 1, 1, 0, \rd, \rs1, 0, \f3, 0, 0
    .endm

/* Packed SIMD (P, a draft). */
    .macro PK op, rd, rs1, rs2              /* padd psub psadd(u) pssub(u) pmin(u) pmax(u) */
    \op x\rd, x\rs1, x\rs2
    EXPECT K_PACKED, 1, 1, 1, \rd, \rs1, \rs2, 0, 0, 0
    .endm

    .macro PKI op, rd, rs1, shamt                   /* pslli psrli psrai: no rs2 */
    \op x\rd, x\rs1, \shamt
    EXPECT K_PACKED, 1, 1, 0, \rd, \rs1, 0, 0, 0, 0
    .endm

    .macro PMUL op, rd, rs1, rs2                    /* pmul.h.b*, pm4add.b, pm2add.h */
    \op x\rd, x\rs1, x\rs2
    EXPECT K_PMUL, 1, 1, 1, \rd, \rs1, \rs2, 0, 0, 0
    .endm

    .macro PMULA op, rd, rs1, rs2                   /* pm4adda.b ...: rd read as rs3 */
    \op x\rd, x\rs1, x\rs2
    EXPECT K_PMUL, 1, 1, 1, \rd, \rs1, \rs2, 0, 0, \rd
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
    /*     imm[11:5] F7_ROT like RORI and CLZ (Zbb), but another funct3: no rotate */
    OPI    addi,  0,     9,  10, F7_ROT << 5
    OPI    andi,  7,     11, 12, (F7_ROT << 5) | 31

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

    /*     rd  offset       calls (rd is x1 or x5): 1, 5 */
    JAL_   1,  -1048576
    JAL_   0,  1048574
    JAL_   31, 4
    JAL_   5,  2048

    /*     rd  rs1 imm      returns (rs1 is x1 or x5, rd is not rs1): 0,1  0,5  5,1;
                            calls (rd is x1 or x5): 5,31  1,1  5,1 */
    JALR_  0,  1,  0
    JALR_  5,  31, -2048
    JALR_  1,  1,  2047
    JALR_  0,  5,  0
    JALR_  5,  1,  4
    JALR_  0,  6,  -4

    /*     op      funct3 rd  rs1 rs2 */
    MULDIV mul,    0,     1,  2,  3
    MULDIV mulh,   1,     31, 30, 29
    MULDIV mulhsu, 2,     0,  31, 1
    MULDIV mulhu,  3,     5,  0,  31
    MULDIV div,    4,     7,  8,  9
    MULDIV divu,   5,     10, 11, 0
    MULDIV rem,    6,     12, 13, 14
    MULDIV remu,   7,     15, 16, 17

#ifdef HAVE_ZBA
    /*     Zba in Mig3Alu (SH1ADD, SH2ADD, SH3ADD), only when the compiler knows Zba:
           op funct3 alt rd rs1 rs2 */
    OP     sh1add, 2,     0,  1,  2,  3
    OP     sh2add, 4,     0,  31, 30, 29
    OP     sh3add, 6,     0,  5,  0,  31
#endif

#ifdef HAVE_ZBB
    /*     Zbb in Mig3Alu (ANDN, ORN, XNOR, MIN, MINU, MAX, MAXU, ROL, ROR, RORI), only when
           the compiler knows Zbb: op funct3 alt rd rs1 rs2; RORI_ rd rs1 shamt */
    OP     andn,   7,     1,  1,  2,  3
    OP     orn,    6,     1,  31, 0,  30
    OP     xnor,   4,     1,  0,  31, 1
    OP     min,    4,     0,  2,  3,  4
    OP     minu,   5,     0,  31, 30, 29
    OP     max,    6,     0,  5,  0,  31
    OP     maxu,   7,     0,  0,  31, 0
    OP     rol,    1,     1,  1,  2,  3
    OP     ror,    5,     1,  31, 30, 0
    RORI_  4,  5,  0
    RORI_  31, 1,  31

    /*       op      rd  rs1   Zbb with one operand, in ComputeCoreBitmanip */
    BITMANIP sext.b, 1,  2
    BITMANIP sext.h, 31, 30
    BITMANIP zext.h, 0,  31
    BITMANIP orc.b,  5,  0
    BITMANIP rev8,   17, 18
    BITMANIP clz,    3,  4
    BITMANIP ctz,    31, 0
    BITMANIP cpop,   0,  31
#endif

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

    /*     rd  rs1 ordering (aq, rl: every access of Mig3 is in order) */
    LR_    1,  2
    LR_    31, 0,  .aq
    LR_    0,  31, .aqrl
    /*     rd  rs2 rs1 */
    SC_    3,  4,  5
    SC_    0,  31, 1,  .rl
    SC_    31, 0,  31, .aqrl
    /*     op         rd  rs2 rs1 */
    AMO_   amoadd.w,  1,  2,  3
    AMO_   amoswap.w, 31, 0,  1,  .aq
    AMO_   amoxor.w,  0,  31, 2,  .rl
    AMO_   amoor.w,   4,  5,  31, .aqrl
    AMO_   amoand.w,  6,  7,  8
    AMO_   amomin.w,  9,  10, 11
    AMO_   amomax.w,  12, 13, 14
    AMO_   amominu.w, 15, 16, 17
    AMO_   amomaxu.w, 18, 19, 0

#ifdef HAVE_ZICBOM
    /*     op         rs1   Zicbom, only when the compiler knows it */
    CBO_   cbo.clean, 1
    CBO_   cbo.flush, 31
    CBO_   cbo.inval, 0
    CBO_   cbo.inval, 17
#endif

#ifdef HAVE_ZFINX
    /*     F on the x registers (Zfinx), only when the compiler knows it; rm names: rne 0,
           rtz 1, rdn 2, rup 3, rmm 4, dyn 7 (frm) */
    FMA4   fmadd.s,   1,  2,  3,  4,  rne, 0
    FMA4   fmsub.s,   31, 30, 29, 28, rtz, 1
    FMA4   fnmsub.s,  0,  31, 0,  31, rdn, 2
    FMA4   fnmadd.s,  5,  6,  7,  8,  dyn, 7
    FP2RM  fadd.s,    9,  10, 11, rup, 3
    FP2RM  fsub.s,    12, 13, 14, rmm, 4
    FP2RM  fmul.s,    15, 16, 17, dyn, 7
    FP2RM  fdiv.s,    18, 19, 20, rne, 0
    FP1RM  fsqrt.s,   21, 22, rtz, 1
    FP2    fsgnj.s,   0,  1,  2,  3
    FP2    fsgnjn.s,  1,  4,  5,  6
    FP2    fsgnjx.s,  2,  7,  8,  9
    FP2    fmin.s,    0,  10, 11, 12
    FP2    fmax.s,    1,  13, 14, 15
    FP2    feq.s,     2,  16, 17, 18
    FP2    flt.s,     1,  19, 20, 21
    FP2    fle.s,     0,  22, 23, 24
    FP1    fclass.s,  1,  25, 26
    FP1RM  fcvt.w.s,  27, 28, rtz, 1
    FP1RM  fcvt.wu.s, 29, 30, dyn, 7
    FP1RM  fcvt.s.w,  31, 1,  rne, 0
    FP1RM  fcvt.s.wu, 2,  3,  rdn, 2
#endif

#ifdef HAVE_P
    /*     Packed SIMD (P, a draft), only when the compiler knows it: op rd rs1 rs2 */
    PK     padd.b, 1,  2,  3
    PK     padd.h, 31, 30, 29
    PK     psub.b, 5,  0,  31
    PK     psub.h, 0,  31, 1
    PK     psadd.b,  2,  3,  4
    PK     psadd.h,  6,  7,  8
    PK     psaddu.b, 9,  10, 11
    PK     psaddu.h, 12, 13, 14
    PK     pssub.b,  15, 16, 17
    PK     pssub.h,  18, 19, 20
    PK     pssubu.b, 21, 22, 23
    PK     pssubu.h, 24, 25, 26
    PK     pmin.b,   27, 28, 29
    PK     pmin.h,   30, 31, 1
    PK     pminu.b,  3,  5,  7
    PK     pminu.h,  9,  11, 13
    PK     pmax.b,   15, 17, 19
    PK     pmax.h,   21, 23, 25
    PK     pmaxu.b,  27, 29, 31
    PK     pmaxu.h,  2,  4,  6
    PKI    pslli.b,  1,  2,  7
    PKI    pslli.h,  3,  4,  15
    PKI    psrli.b,  5,  6,  0
    PKI    psrli.h,  7,  8,  9
    PKI    psrai.b,  9,  10, 3
    PKI    psrai.h,  11, 12, 12
    PK     psll.bs,  13, 14, 15
    PK     psll.hs,  16, 17, 18
    PK     psrl.bs,  19, 20, 21
    PK     psrl.hs,  22, 23, 24
    PK     psra.bs,  25, 26, 27
    PK     psra.hs,  28, 29, 30
    PMUL   pmul.h.b00,   1,  2,  3
    PMUL   pmul.h.b01,   4,  5,  6
    PMUL   pmul.h.b11,   7,  8,  9
    PMUL   pmulu.h.b00,  10, 11, 12
    PMUL   pmulu.h.b01,  13, 14, 15
    PMUL   pmulu.h.b11,  16, 17, 18
    PMUL   pmulsu.h.b00, 19, 20, 21
    PMUL   pmulsu.h.b11, 22, 23, 31
    PMUL   pm4add.b,     24, 25, 26
    PMUL   pm4addu.b,    27, 28, 29
    PMUL   pm4addsu.b,   30, 31, 1
    PMUL   pm2add.h,     2,  3,  4
    PMUL   pm2addu.h,    5,  6,  7
    PMUL   pm2addsu.h,   8,  9,  10
    PMULA  pm4adda.b,    11, 12, 13
    PMULA  pm4addau.b,   14, 15, 16
    PMULA  pm4addasu.b,  17, 18, 19
    PMULA  pm2adda.h,    20, 21, 22
    PMULA  pm2addau.h,   23, 24, 25
    PMULA  pm2addasu.h,  26, 27, 28
    PMUL   pmulh.h,      29, 30, 31
    PMUL   pmulhu.h,     1,  3,  5
    PMUL   pmulhsu.h,    7,  9,  11
    PMUL   pmulhr.h,     13, 15, 17
    PMUL   pmulhru.h,    19, 21, 23
    PMUL   pmulhrsu.h,   25, 27, 29
    PMUL   pmulq.h,      31, 2,  4
    PMUL   pmulqr.h,     6,  8,  10
#endif

    ILLEGAL 0x00000000      /* all zeros: defined to be illegal */
    ILLEGAL 0xffffffff      /* all ones: defined to be illegal */
    ILLEGAL 0xfe000033      /* OP with funct7 = 0x7f: neither OP nor M */
    ILLEGAL 0x0000100f      /* fence.i: Zifencei extension */
    ILLEGAL 0x00200073      /* like ecall and ebreak, but imm=2 */
    ILLEGAL 0x0000000b      /* custom-0 opcode */
    ILLEGAL 0x60701013      /* like sext.b (OP-IMM, imm[11:5] F7_ROT, funct3 1), rs2 field 7 */
    ILLEGAL 0x0000302f      /* amoadd.d: RV64 */
    ILLEGAL 0x1010202f      /* like lr.w, but rs2 field 1 */
    ILLEGAL 0x1000302f      /* lr.d: RV64 */
    ILLEGAL 0x0040200f      /* cbo.zero: Zicboz */
    ILLEGAL 0x0030200f      /* like cbo.clean, but imm 3 */
    ILLEGAL 0x0010208f      /* like cbo.clean, but rd field 1 */
    ILLEGAL 0x00002007      /* flw: F, not Zfinx */
    ILLEGAL 0x00002027      /* fsw: F, not Zfinx */
    ILLEGAL 0xe0000053      /* fmv.x.w: F, not Zfinx */
    ILLEGAL 0xf0000053      /* fmv.w.x: F, not Zfinx */
    ILLEGAL 0x00005053      /* like fadd.s, but rm 101 (reserved) */
    ILLEGAL 0x00006043      /* like fmadd.s, but rm 110 (reserved) */
    ILLEGAL 0x58100053      /* like fsqrt.s, but rs2 field 1 */
    ILLEGAL 0x02000053      /* fadd.d: D, not in Mig3 */
cases_end:

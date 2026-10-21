/* RISC-V instruction formats: fields of a 32-bit instruction, as in the
 * format tables of the RISC-V spec.
 *
 * Assign an instruction to insn_fmt_t.word and read the fields of a format,
 * for example f.b.imm_12; immediate bits keep the spec names (imm_10_5 is imm[10:5]).
 * F3_* are the funct3 values that select the operation inside an opcode,
 * CAUSE_* the exception codes of mcause (privileged spec).
 * Encodings of instructions are in RiscvInstrPkg, CSR addresses in RiscvCsrPkg
 * (both generated from riscv-opcodes).
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
package RiscvPkg;

    // funct3: selects the operation inside an opcode (F3_* below).
    typedef logic [2:0] funct3_t;

    // funct3 by opcode, RV32I. Not every user needs every group.
    /* verilator lint_off UNUSEDPARAM */

    // OP and OP-IMM; alt (insn[30]) selects SUB and SRA/SRAI.
    localparam funct3_t F3_ADD_SUB = 3'b000;
    localparam funct3_t F3_SLL     = 3'b001;
    localparam funct3_t F3_SLT     = 3'b010;
    localparam funct3_t F3_SLTU    = 3'b011;
    localparam funct3_t F3_XOR     = 3'b100;
    localparam funct3_t F3_SRL_SRA = 3'b101;
    localparam funct3_t F3_OR      = 3'b110;
    localparam funct3_t F3_AND     = 3'b111;

    // BRANCH.
    localparam funct3_t F3_BEQ     = 3'b000;
    localparam funct3_t F3_BNE     = 3'b001;
    localparam funct3_t F3_BLT     = 3'b100;
    localparam funct3_t F3_BGE     = 3'b101;
    localparam funct3_t F3_BLTU    = 3'b110;
    localparam funct3_t F3_BGEU    = 3'b111;

    // LOAD and STORE: access width; U loads zero-extend.
    localparam funct3_t F3_B       = 3'b000;
    localparam funct3_t F3_H       = 3'b001;
    localparam funct3_t F3_W       = 3'b010;
    localparam funct3_t F3_BU      = 3'b100;
    localparam funct3_t F3_HU      = 3'b101;

    // SYSTEM, Zicsr: operation on a CSR; the I forms take a 5-bit immediate (the rs1 field).
    localparam funct3_t F3_CSRRW   = 3'b001;
    localparam funct3_t F3_CSRRS   = 3'b010;
    localparam funct3_t F3_CSRRC   = 3'b011;
    localparam funct3_t F3_CSRRWI  = 3'b101;
    localparam funct3_t F3_CSRRSI  = 3'b110;
    localparam funct3_t F3_CSRRCI  = 3'b111;

    // OP with funct7 = 1, M extension: multiply and divide.
    localparam funct3_t F3_MUL     = 3'b000;
    localparam funct3_t F3_MULH    = 3'b001;
    localparam funct3_t F3_MULHSU  = 3'b010;
    localparam funct3_t F3_MULHU   = 3'b011;
    localparam funct3_t F3_DIV     = 3'b100;
    localparam funct3_t F3_DIVU    = 3'b101;
    localparam funct3_t F3_REM     = 3'b110;
    localparam funct3_t F3_REMU    = 3'b111;

    // Exception codes of mcause (interrupt bit 0), privileged spec; names as in riscv-opcodes.
    localparam logic [4:0] CAUSE_MISALIGNED_FETCH    = 5'd0;
    localparam logic [4:0] CAUSE_FETCH_ACCESS        = 5'd1;
    localparam logic [4:0] CAUSE_ILLEGAL_INSTRUCTION = 5'd2;
    localparam logic [4:0] CAUSE_BREAKPOINT          = 5'd3;
    localparam logic [4:0] CAUSE_MISALIGNED_LOAD     = 5'd4;
    localparam logic [4:0] CAUSE_LOAD_ACCESS         = 5'd5;
    localparam logic [4:0] CAUSE_MISALIGNED_STORE    = 5'd6;
    localparam logic [4:0] CAUSE_STORE_ACCESS        = 5'd7;
    localparam logic [4:0] CAUSE_USER_ECALL          = 5'd8;
    localparam logic [4:0] CAUSE_SUPERVISOR_ECALL    = 5'd9;
    localparam logic [4:0] CAUSE_MACHINE_ECALL       = 5'd11;

    /* verilator lint_on UNUSEDPARAM */

    typedef struct packed {     // R-type: OP
        logic [6:0] funct7;
        logic [4:0] rs2;
        logic [4:0] rs1;
        funct3_t    funct3;
        logic [4:0] rd;
        logic [6:0] opcode;
    } insn_r_t;

    typedef struct packed {     // I-type: OP-IMM, LOAD, JALR
        logic [11:0] imm_11_0;
        logic [4:0]  rs1;
        funct3_t     funct3;
        logic [4:0]  rd;
        logic [6:0]  opcode;
    } insn_i_t;

    typedef struct packed {     // S-type: STORE
        logic [6:0] imm_11_5;
        logic [4:0] rs2;
        logic [4:0] rs1;
        funct3_t    funct3;
        logic [4:0] imm_4_0;
        logic [6:0] opcode;
    } insn_s_t;

    typedef struct packed {     // B-type: BRANCH
        logic       imm_12;
        logic [5:0] imm_10_5;
        logic [4:0] rs2;
        logic [4:0] rs1;
        funct3_t    funct3;
        logic [3:0] imm_4_1;
        logic       imm_11;
        logic [6:0] opcode;
    } insn_b_t;

    typedef struct packed {     // U-type: LUI, AUIPC
        logic [19:0] imm_31_12;
        logic [4:0]  rd;
        logic [6:0]  opcode;
    } insn_u_t;

    typedef struct packed {     // J-type: JAL
        logic       imm_20;
        logic [9:0] imm_10_1;
        logic       imm_11;
        logic [7:0] imm_19_12;
        logic [4:0] rd;
        logic [6:0] opcode;
    } insn_j_t;

    // One instruction seen in every format: assign word, read the fields of a format.
    typedef union packed {
        logic [31:0] word;
        insn_r_t     r;
        insn_i_t     i;
        insn_s_t     s;
        insn_b_t     b;
        insn_u_t     u;
        insn_j_t     j;
    } insn_fmt_t;

endpackage

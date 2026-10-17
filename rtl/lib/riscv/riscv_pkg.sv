/* RISC-V instruction formats: fields of a 32-bit instruction, as in the
 * format tables of the RISC-V spec.
 *
 * Assign an instruction to insn_fmt_t.word and read the fields of a format,
 * for example f.b.imm_12; immediate bits keep the spec names (imm_10_5 is imm[10:5]).
 * Encodings of instructions are in RiscvInstrPkg (generated from riscv-opcodes).
 */
package RiscvPkg;

    typedef struct packed {     // R-type: OP
        logic [6:0] funct7;
        logic [4:0] rs2;
        logic [4:0] rs1;
        logic [2:0] funct3;
        logic [4:0] rd;
        logic [6:0] opcode;
    } insn_r_t;

    typedef struct packed {     // I-type: OP-IMM, LOAD, JALR
        logic [11:0] imm_11_0;
        logic [4:0]  rs1;
        logic [2:0]  funct3;
        logic [4:0]  rd;
        logic [6:0]  opcode;
    } insn_i_t;

    typedef struct packed {     // S-type: STORE
        logic [6:0] imm_11_5;
        logic [4:0] rs2;
        logic [4:0] rs1;
        logic [2:0] funct3;
        logic [4:0] imm_4_0;
        logic [6:0] opcode;
    } insn_s_t;

    typedef struct packed {     // B-type: BRANCH
        logic       imm_12;
        logic [5:0] imm_10_5;
        logic [4:0] rs2;
        logic [4:0] rs1;
        logic [2:0] funct3;
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

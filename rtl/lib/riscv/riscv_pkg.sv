/* RISC-V instruction formats: fields of a 32-bit instruction, as in the
 * format tables of the RISC-V spec.
 *
 * Assign an instruction to insn_fmt_t.word and read the fields of a format,
 * for example f.b.imm_12; immediate bits keep the spec names (imm_10_5 is imm[10:5]).
 * imm_i_of, imm_s_of, imm_b_of, imm_u_of, imm_j_of give the immediate of an instruction,
 * sign-extended to 32 bits; for RV64 sign-extend it to 64: imm = sext64(imm_i_of(insn)).
 * F3_* are the funct3 values that select the operation inside an opcode,
 * CAUSE_* the exception codes of mcause, MISA_* and MSTATUS_* fields of these CSRs
 * (privileged spec), REG_* integer registers by ABI name; alt_of and csr_read_only read a
 * bit the spec gives a meaning.
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

    typedef logic [4:0] excp_code_t;     // Exception Code of mcause: why a trap was taken

    // Exception codes of mcause (interrupt bit 0), privileged spec; names as in riscv-opcodes.
    localparam excp_code_t CAUSE_MISALIGNED_FETCH    = 5'd0;
    localparam excp_code_t CAUSE_FETCH_ACCESS        = 5'd1;
    localparam excp_code_t CAUSE_ILLEGAL_INSTRUCTION = 5'd2;
    localparam excp_code_t CAUSE_BREAKPOINT          = 5'd3;
    localparam excp_code_t CAUSE_MISALIGNED_LOAD     = 5'd4;
    localparam excp_code_t CAUSE_LOAD_ACCESS         = 5'd5;
    localparam excp_code_t CAUSE_MISALIGNED_STORE    = 5'd6;
    localparam excp_code_t CAUSE_STORE_ACCESS        = 5'd7;
    localparam excp_code_t CAUSE_USER_ECALL          = 5'd8;
    localparam excp_code_t CAUSE_SUPERVISOR_ECALL    = 5'd9;
    localparam excp_code_t CAUSE_MACHINE_ECALL       = 5'd11;

    // Integer registers by ABI name, those a design or a test needs: x1 (ra) and x5 (t0)
    // are the link registers of the return-address hints of JAL and JALR, a0 and a1 the
    // first arguments (semihosting).
    localparam logic [4:0] REG_RA = 5'd1;
    localparam logic [4:0] REG_T0 = 5'd5;
    localparam logic [4:0] REG_A0 = 5'd10;
    localparam logic [4:0] REG_A1 = 5'd11;

    // misa: MXL in the two top bits (1: XLEN 32), one bit per extension, its letter - 'A'.
    localparam logic [1:0] MISA_MXL_32 = 2'd1;
    localparam int         MISA_EXT_I  = "I" - "A";
    localparam int         MISA_EXT_M  = "M" - "A";

    // mstatus: bit of MIE, of MPIE, and the low bit of MPP (2 bits: the privilege before
    // the trap); PRIV_M is machine mode.
    localparam int         MSTATUS_MIE  = 3;
    localparam int         MSTATUS_MPIE = 7;
    localparam int         MSTATUS_MPP  = 11;
    localparam logic [1:0] PRIV_M       = 2'd3;

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

    typedef logic [31:0] riscv_insn_t;      // instruction word, 32 bits also in RV64

    // One instruction seen in every format: assign word, read the fields of a format.
    typedef union packed {
        riscv_insn_t word;
        insn_r_t     r;
        insn_i_t     i;
        insn_s_t     s;
        insn_b_t     b;
        insn_u_t     u;
        insn_j_t     j;
    } insn_fmt_t;

    // Immediates of the instruction formats, sign-extended to 32 bits; insn is the
    // instruction word. Every immediate is a 32-bit value sign-extended to XLEN, also in
    // RV64:
    // RV64 imm = sext64(imm_i_of(insn));
    function automatic logic [31:0] imm_i_of(riscv_insn_t insn);
        insn_fmt_t f;
        f.word = insn;
        return {{20{f.i.imm_11_0[11]}}, f.i.imm_11_0};
    endfunction

    function automatic logic [31:0] imm_s_of(riscv_insn_t insn);
        insn_fmt_t f;
        f.word = insn;
        return {{20{f.s.imm_11_5[6]}}, f.s.imm_11_5, f.s.imm_4_0};
    endfunction

    function automatic logic [31:0] imm_b_of(riscv_insn_t insn);
        insn_fmt_t f;
        f.word = insn;
        return {{19{f.b.imm_12}}, f.b.imm_12, f.b.imm_11, f.b.imm_10_5, f.b.imm_4_1, 1'b0};
    endfunction

    function automatic logic [31:0] imm_u_of(riscv_insn_t insn);
        insn_fmt_t f;
        f.word = insn;
        return {f.u.imm_31_12, 12'b0};
    endfunction

    function automatic logic [31:0] imm_j_of(riscv_insn_t insn);
        insn_fmt_t f;
        f.word = insn;
        return {{11{f.j.imm_20}}, f.j.imm_20, f.j.imm_19_12, f.j.imm_11, f.j.imm_10_1, 1'b0};
    endfunction

    // alt: insn[30], bit 5 of funct7, selects SUB instead of ADD and SRA/SRAI instead of
    // SRL/SRLI (and marks ANDN, ORN, XNOR of Zbb).
    function automatic logic alt_of(riscv_insn_t insn);
        insn_fmt_t f;
        f.word = insn;
        return f.r.funct7[5];
    endfunction

    // A CSR is read-only when bits 11:10 of its address are 11 (privileged spec, CSR map);
    // the other bits of the address do not matter.
    /* verilator lint_off UNUSEDSIGNAL */
    function automatic logic csr_read_only(logic [11:0] addr);
        return addr[11:10] == 2'b11;
    endfunction
    /* verilator lint_on UNUSEDSIGNAL */

    // A 32-bit value sign-extended to 64 bits: an immediate for RV64 (XLEN = 64).
    function automatic logic [63:0] sext64(logic [31:0] v);
        return {{32{v[31]}}, v};
    endfunction

endpackage

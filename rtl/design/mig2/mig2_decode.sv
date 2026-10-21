/* Mig2 decode: instruction -> decoded_t, purely combinational.
 *
 * kind comes from exact match with the RISC-V encodings of RiscvInstrPkg
 * (generated from riscv-opcodes), so every other word is KIND_ILLEGAL.
 * Register numbers, funct3, alt and immediates come straight from instruction
 * fields (RiscvPkg formats), at the same place for every instruction. Decode
 * computes the controls of every part, grouped in decoded_t (the table below); parts
 * use funct3 and alt only to choose an operation within their part. Immediates are for RV32:
 * U-type is not sign-extended beyond 32 bits.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module Mig2Decode import Mig2Pkg::*, RiscvPkg::*; (
    input  insn_t                 insn,
    output decoded_t              dec
);
    import RiscvInstrPkg::*;

    kind_t kind;

    always_comb
        casez (insn)
            LUI:                                                    kind = KIND_LUI;
            AUIPC:                                                  kind = KIND_AUIPC;
            JAL:                                                    kind = KIND_JAL;
            JALR:                                                   kind = KIND_JALR;
            BEQ, BNE, BLT, BGE, BLTU, BGEU:                         kind = KIND_BRANCH;
            LB, LH, LW, LBU, LHU:                                   kind = KIND_LOAD;
            SB, SH, SW:                                             kind = KIND_STORE;
            ADDI, SLTI, SLTIU, XORI, ORI, ANDI, SLLI, SRLI, SRAI:   kind = KIND_OP_IMM;
            ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND:       kind = KIND_OP;
            FENCE:                                                  kind = KIND_FENCE;
            ECALL:                                                  kind = KIND_ECALL;
            EBREAK:                                                 kind = KIND_EBREAK;
            CSRRW, CSRRS, CSRRC, CSRRWI, CSRRSI, CSRRCI:             kind = KIND_CSR;
            MUL, MULH, MULHSU, MULHU, DIV, DIVU, REM, REMU:         kind = KIND_MULDIV;
            MRET:                                                   kind = KIND_MRET;
            WFI:                                                    kind = KIND_WFI;
            default:                                                kind = KIND_ILLEGAL;
        endcase

    // The instruction seen in every format.
    insn_fmt_t f;
    assign f.word = insn;

    // Immediates of the formats, sign-extended.
    word_t imm_i;
    word_t imm_s;
    word_t imm_b;
    word_t imm_u;
    word_t imm_j;
    assign imm_i = {{(WIDTH-12){f.i.imm_11_0[11]}}, f.i.imm_11_0};
    assign imm_s = {{(WIDTH-12){f.s.imm_11_5[6]}},  f.s.imm_11_5, f.s.imm_4_0};
    assign imm_b = {{(WIDTH-13){f.b.imm_12}},       f.b.imm_12, f.b.imm_11, f.b.imm_10_5, f.b.imm_4_1, 1'b0};
    assign imm_u = {f.u.imm_31_12, 12'b0};
    assign imm_j = {{(WIDTH-21){f.j.imm_20}},       f.j.imm_20, f.j.imm_19_12, f.j.imm_11, f.j.imm_10_1, 1'b0};

    // CSR instructions: the CSR address, not sign-extended (0xc00 is not negative);
    // register forms read rs1, the I forms use the rs1 field as immediate.
    word_t imm_csr;
    logic  csr_reg;
    assign imm_csr = {{(WIDTH-12){1'b0}}, f.i.imm_11_0};
    assign csr_reg = f.i.funct3 == F3_CSRRW || f.i.funct3 == F3_CSRRS || f.i.funct3 == F3_CSRRC;

    // Fields at the same place in every format, with short names for the table below.
    reg_id_t    rd;
    reg_id_t    rs1;
    reg_id_t    rs2;
    funct3_t    funct3;
    logic       alt;
    assign rd     = f.r.rd;
    assign rs1    = f.r.rs1;
    assign rs2    = f.r.rs2;
    assign funct3 = f.r.funct3;
    assign alt    = f.r.funct7[5];   // insn[30]: SUB, SRA, SRAI

    always_comb begin
        dec.kind   = kind;
        dec.rd     = rd;
        dec.rs1    = rs1;
        dec.rs2    = rs2;
        dec.funct3 = funct3;
        dec.alt    = alt;

        // Per kind: registers written and read, source of rd, format of the immediate,
        // controls of the parts. Defaults: nothing written or read, I-type immediate,
        // ALU adds rs1 + imm, no other control.
        dec.rd_we    = 1'b0;
        dec.rd_src   = RD_ALU;
        dec.uses_rs1 = 1'b0;
        dec.uses_rs2 = 1'b0;
        dec.imm      = imm_i;         // JALR, LOAD, OP_IMM (shifts: imm[4:0] is shamt)
        dec.alu      = '{a: A_RS1, b_imm: 1'b1, op: 1'b0, sub: 1'b0};
        dec.br       = '0;
        dec.mem      = '0;
        dec.sys      = '0;
        dec.muldiv   = 1'b0;
        case (kind)
            KIND_LUI: begin
                dec.rd_we = 1'b1;  dec.imm = imm_u;  dec.alu.a = A_ZERO;
            end
            KIND_AUIPC: begin
                dec.rd_we = 1'b1;  dec.imm = imm_u;  dec.alu.a = A_PC;
            end
            KIND_JAL: begin
                dec.rd_we = 1'b1;  dec.rd_src = RD_LINK;  dec.imm = imm_j;  dec.br.jump = 1'b1;
            end
            KIND_JALR: begin
                dec.rd_we = 1'b1;  dec.rd_src = RD_LINK;  dec.uses_rs1 = 1'b1;
                dec.br.jump = 1'b1;  dec.br.target_rs1 = 1'b1;
            end
            KIND_BRANCH: begin
                dec.uses_rs1 = 1'b1;  dec.uses_rs2 = 1'b1;  dec.imm = imm_b;  dec.br.branch = 1'b1;
            end
            KIND_LOAD: begin
                dec.rd_we = 1'b1;  dec.rd_src = RD_LOAD;  dec.uses_rs1 = 1'b1;  dec.mem.read = 1'b1;
            end
            KIND_STORE: begin
                dec.uses_rs1 = 1'b1;  dec.uses_rs2 = 1'b1;  dec.imm = imm_s;  dec.mem.write = 1'b1;
            end
            KIND_OP_IMM: begin
                dec.rd_we = 1'b1;  dec.uses_rs1 = 1'b1;  dec.alu.op = 1'b1;
            end
            KIND_OP: begin
                dec.rd_we = 1'b1;  dec.uses_rs1 = 1'b1;  dec.uses_rs2 = 1'b1;
                dec.alu = '{a: A_RS1, b_imm: 1'b0, op: 1'b1, sub: alt};
            end
            KIND_MULDIV: begin
                dec.rd_we = 1'b1;  dec.rd_src = RD_MULDIV;  dec.uses_rs1 = 1'b1;  dec.uses_rs2 = 1'b1;
                dec.muldiv = 1'b1;
            end
            KIND_CSR: begin
                dec.rd_we = 1'b1;  dec.rd_src = RD_CSR;  dec.uses_rs1 = csr_reg;  dec.imm = imm_csr;
                dec.sys.csr = 1'b1;
            end
            KIND_ECALL:   dec.sys.ecall   = 1'b1;
            KIND_EBREAK:  dec.sys.ebreak  = 1'b1;
            KIND_MRET:    dec.sys.mret    = 1'b1;
            KIND_ILLEGAL: dec.sys.illegal = 1'b1;
            default: ;  // FENCE, WFI: no-ops
        endcase
    end

endmodule

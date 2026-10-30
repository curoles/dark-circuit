/* Mig2 decode: instruction -> decoded_t, purely combinational.
 *
 * kind comes from exact match with the RISC-V encodings of RiscvInstrPkg
 * (generated from riscv-opcodes), so every other word is KIND_ILLEGAL.
 * Register numbers, funct3, alt and immediates come straight from instruction
 * fields (RiscvPkg formats), at the same place for every instruction. Decode
 * computes the controls of every part, grouped in decoded_t (the table below); parts
 * use funct3 and alt only to choose an operation within their part. The immediates come from
 * RiscvPkg (imm_*_of), sign-extended to 32 bits.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module Mig2Decode import Mig2Pkg::*, RiscvPkg::*; (
    input  insn_t    insn,  // instruction word
    output decoded_t dec    // the instruction taken apart: fields, immediate, controls
);
    import RiscvInstrPkg::*;
    import Alu2Pkg::*;

    kind_e kind;    // instruction group, from the exact encodings: decides the controls

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
            RORI_RV32:                                              kind = KIND_OP_IMM;  // Zbb
            ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND:       kind = KIND_OP;
            ANDN, ORN, XNOR, MIN, MINU, MAX, MAXU, ROL, ROR:        kind = KIND_OP;  // Zbb
            FENCE:                                                  kind = KIND_FENCE;
            ECALL:                                                  kind = KIND_ECALL;
            EBREAK:                                                 kind = KIND_EBREAK;
            CSRRW, CSRRS, CSRRC, CSRRWI, CSRRSI, CSRRCI:             kind = KIND_CSR;
            MUL, MULH, MULHSU, MULHU, DIV, DIVU, REM, REMU:         kind = KIND_MULDIV;
            SEXT_B, SEXT_H, ZEXT_H_RV32, ORC_B, REV8_RV32:          kind = KIND_BITMANIP;
            CLZ, CTZ, CPOP:                                         kind = KIND_BITMANIP;
            MRET:                                                   kind = KIND_MRET;
            WFI:                                                    kind = KIND_WFI;
            default:                                                kind = KIND_ILLEGAL;
        endcase

    // The instruction seen in every format.
    insn_fmt_t f;
    assign f.word = insn;

    // CSR instructions: the CSR address, not sign-extended (0xc00 is not negative);
    // register forms read rs1, the I forms use the rs1 field as immediate.
    word_t imm_csr;
    logic  csr_reg;
    assign imm_csr = {{(WIDTH-12){1'b0}}, f.i.imm_11_0};
    assign csr_reg = f.i.funct3 == F3_CSRRW || f.i.funct3 == F3_CSRRS || f.i.funct3 == F3_CSRRC;

    // @kb: rtl/design/mig2/imm_by_opcode
    // The immediate by format. The format follows from the opcode alone, so the immediate
    // does not wait for kind, the match of all encodings: ID's target pc + imm is on the
    // longest path. Opcodes from the encodings: the low 7 bits of an instruction of the
    // format.
    word_t imm;
    always_comb
        case (f.r.opcode)
            LUI[6:0], AUIPC[6:0]: imm = imm_u_of(insn);
            JAL[6:0]:             imm = imm_j_of(insn);
            BEQ[6:0]:             imm = imm_b_of(insn);     // branches
            SW[6:0]:              imm = imm_s_of(insn);     // stores
            CSRRW[6:0]:           imm = imm_csr;            // SYSTEM: the CSR address
            default:              imm = imm_i_of(insn);     // JALR, loads, OP-IMM, FENCE
        endcase

    // Controls of an M instruction from its funct3.
    function automatic muldiv_ctrl_t muldiv_of(funct3_t f3);
        muldiv_ctrl_t m;
        m.en         = 1'b1;
        m.div        = f3 == F3_DIV || f3 == F3_DIVU || f3 == F3_REM || f3 == F3_REMU;
        m.rem        = f3 == F3_REM || f3 == F3_REMU;
        m.mul_lo     = f3 == F3_MUL;
        m.a_signed   = f3 == F3_MULH || f3 == F3_MULHSU;
        m.b_signed   = f3 == F3_MULH;
        m.div_signed = f3 == F3_DIV || f3 == F3_REM;
        return m;
    endfunction

    // @kb: rtl/design/mig2/zbb_reuse
    // The operation of Alu2 (Mig2Alu), by the encodings: OP and OP-IMM, also the Zbb that
    // reuse the ALU (ANDN, ORN, XNOR, MIN, MINU, MAX, MAXU, ROL, ROR, RORI); a + b for every
    // other instruction (LUI, AUIPC, loads, stores, JALR). Its controls (ctrl_of) go to EX
    // in decoded_t: Alu2 decodes nothing.
    function automatic op_e alu_op_of(insn_t w);
        casez (w)
            SUB:                return ALU2_SUB;
            SLL, SLLI:          return ALU2_SLL;
            SLT, SLTI:          return ALU2_SLT;
            SLTU, SLTIU:        return ALU2_SLTU;
            XOR, XORI:          return ALU2_XOR;
            SRL, SRLI:          return ALU2_SRL;
            SRA, SRAI:          return ALU2_SRA;
            OR, ORI:            return ALU2_OR;
            AND, ANDI:          return ALU2_AND;
            ANDN:               return ALU2_ANDN;
            ORN:                return ALU2_ORN;
            XNOR:               return ALU2_XNOR;
            MIN:                return ALU2_MIN;
            MINU:               return ALU2_MINU;
            MAX:                return ALU2_MAX;
            MAXU:               return ALU2_MAXU;
            ROL:                return ALU2_ROL;
            ROR, RORI_RV32:     return ALU2_ROR;
            default:            return ALU2_ADD;    // ADD, ADDI and the address sums
        endcase
    endfunction

    // Zbb with one operand, in ComputeCoreBitmanip: its operation, by the encodings.
    function automatic ComputeCoreBitmanipPkg::bm_op_e bitmanip_of(insn_t w);
        casez (w)
            SEXT_B:      return ComputeCoreBitmanipPkg::BM_SEXT_B;
            SEXT_H:      return ComputeCoreBitmanipPkg::BM_SEXT_H;
            ZEXT_H_RV32: return ComputeCoreBitmanipPkg::BM_ZEXT_H;
            ORC_B:       return ComputeCoreBitmanipPkg::BM_ORC_B;
            REV8_RV32:   return ComputeCoreBitmanipPkg::BM_REV8;
            CLZ:         return ComputeCoreBitmanipPkg::BM_CLZ;
            CTZ:         return ComputeCoreBitmanipPkg::BM_CTZ;
            CPOP:        return ComputeCoreBitmanipPkg::BM_CPOP;
            default:     return ComputeCoreBitmanipPkg::bm_op_e'('0);  // other kinds: not used
        endcase
    endfunction

    // Link register of the return-address hints of JAL/JALR: x1 (ra) or x5 (t0). A JAL or
    // JALR that writes a link register is a call (it pushes the return-address stack), a JALR
    // that reads one is a return (it pops), both for a swap (a coroutine: pop, then push).
    function automatic logic is_link(reg_id_t r);
        return r == REG_RA || r == REG_T0;
    endfunction

    always_comb begin
        // Fields at the same place in every format.
        dec.kind   = kind;
        dec.rd     = f.r.rd;
        dec.rs1    = f.r.rs1;
        dec.rs2    = f.r.rs2;
        dec.funct3 = f.r.funct3;
        dec.alt    = alt_of(insn);     // insn[30]: SUB, SRA, SRAI

        // Per kind: registers written and read, source of rd, format of the immediate,
        // controls of the parts. Defaults: nothing written or read, I-type immediate,
        // ALU adds rs1 + imm, no other control.
        dec.rd_we    = 1'b0;
        dec.rd_src   = RD_ALU;
        dec.uses_rs1 = 1'b0;
        dec.uses_rs2 = 1'b0;
        dec.imm      = imm;              // by opcode (shifts: imm[4:0] is shamt)
        dec.alu      = '{a: A_RS1, b_imm: 1'b1, alu2: ctrl_of(alu_op_of(insn))};
        dec.br       = '0;
        dec.mem      = '0;
        dec.sys      = '0;
        dec.muldiv   = '0;
        dec.bitmanip = ComputeCoreBitmanipPkg::bm_op_e'('0);
        case (kind)
            KIND_LUI: begin
                dec.rd_we = 1'b1;  dec.alu.a = A_ZERO;
            end
            KIND_AUIPC: begin
                dec.rd_we = 1'b1;  dec.alu.a = A_PC;
            end
            KIND_JAL: begin
                dec.rd_we = 1'b1;  dec.rd_src = RD_LINK;
                dec.br.jump = 1'b1;  dec.br.call = is_link(dec.rd);
            end
            KIND_JALR: begin
                dec.rd_we = 1'b1;  dec.rd_src = RD_LINK;  dec.uses_rs1 = 1'b1;
                dec.br.jump = 1'b1;  dec.br.target_rs1 = 1'b1;
                // A return pops the return-address stack: rs1 is a link, rd is not rs1.
                dec.br.ret = is_link(dec.rs1) && (!is_link(dec.rd) || dec.rd != dec.rs1);
                dec.br.call = is_link(dec.rd);
            end
            KIND_BRANCH: begin
                dec.uses_rs1 = 1'b1;  dec.uses_rs2 = 1'b1;
                dec.br.branch = 1'b1;
            end
            KIND_LOAD: begin
                dec.rd_we = 1'b1;  dec.rd_src = RD_LOAD;  dec.uses_rs1 = 1'b1;  dec.mem.read = 1'b1;
            end
            KIND_STORE: begin
                dec.uses_rs1 = 1'b1;  dec.uses_rs2 = 1'b1;
                dec.mem.write = 1'b1;
            end
            KIND_OP_IMM: begin
                dec.rd_we = 1'b1;  dec.uses_rs1 = 1'b1;
            end
            KIND_OP: begin
                dec.rd_we = 1'b1;  dec.uses_rs1 = 1'b1;  dec.uses_rs2 = 1'b1;
                dec.alu.b_imm = 1'b0;
            end
            KIND_MULDIV: begin
                dec.rd_we = 1'b1;  dec.rd_src = RD_MULDIV;
                dec.uses_rs1 = 1'b1;  dec.uses_rs2 = 1'b1;  dec.muldiv = muldiv_of(dec.funct3);
            end
            KIND_BITMANIP: begin
                dec.rd_we = 1'b1;  dec.rd_src = RD_BITMANIP;  dec.uses_rs1 = 1'b1;
                dec.bitmanip = bitmanip_of(insn);
            end
            KIND_CSR: begin
                dec.rd_we = 1'b1;  dec.rd_src = RD_CSR;  dec.uses_rs1 = csr_reg;
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

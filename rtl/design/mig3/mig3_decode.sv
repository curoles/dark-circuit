/* Mig3 decode: instruction -> decoded_t, purely combinational.
 *
 * kind comes from exact match with the RISC-V encodings of RiscvInstrPkg
 * (generated from riscv-opcodes), so every other word is KIND_ILLEGAL.
 * Register numbers, funct3, alt and immediates come straight from instruction
 * fields (RiscvPkg formats), at the same place for every instruction. Decode
 * computes the controls of every part, grouped in decoded_t (the table below); parts
 * use funct3 and alt only to choose an operation within their part. The immediates come from
 * RiscvPkg (imm_*_of), sign-extended to 32 bits. LR.W and SC.W (Zalrsc) are a load and
 * a store whose address is rs1 (imm 0), with dec.atomic for Mig3Atomic; an AMO (Zaamo)
 * is a load of rs1 to rd with its operation in dec.atomic.atop, done in front of the
 * memory (kb rtl/design/mig3/amo); a CBO (Zicbom: cbo.clean, cbo.flush, cbo.inval) a store
 * of rs1 (imm 0) that writes no byte, its operation in dec.mem.cmo (kb
 * rtl/design/mig3/cbo); an F instruction (Zfinx: on the x registers) its FPU unit and
 * operation in dec.fp, rs3 for the R4 forms, rd_src RD_FP; FLW, FSW, FMV.X.W and FMV.W.X
 * are not in Zfinx, and a reserved rm field (101, 110) is illegal (kb
 * rtl/design/mig3/fp_decode).
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module Mig3Decode import Mig3Pkg::*, RiscvPkg::*; (
    input  insn_t    insn,  // instruction word
    output decoded_t dec    // the instruction taken apart: fields, immediate, controls
);
    import RiscvInstrPkg::*;
    import Alu2Pkg::*;

    kind_e kind_enc;    // instruction group, from the exact encodings
    kind_e kind;        // the same, an F instruction with a reserved rm illegal: decides
                        // the controls

    always_comb
        casez (insn)
            LUI:                                                    kind_enc = KIND_LUI;
            AUIPC:                                                  kind_enc = KIND_AUIPC;
            JAL:                                                    kind_enc = KIND_JAL;
            JALR:                                                   kind_enc = KIND_JALR;
            BEQ, BNE, BLT, BGE, BLTU, BGEU:                         kind_enc = KIND_BRANCH;
            LB, LH, LW, LBU, LHU:                                   kind_enc = KIND_LOAD;
            SB, SH, SW:                                             kind_enc = KIND_STORE;
            ADDI, SLTI, SLTIU, XORI, ORI, ANDI, SLLI, SRLI, SRAI:   kind_enc = KIND_OP_IMM;
            RORI_RV32:                                              kind_enc = KIND_OP_IMM;  // Zbb
            ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND:       kind_enc = KIND_OP;
            ANDN, ORN, XNOR, MIN, MINU, MAX, MAXU, ROL, ROR:        kind_enc = KIND_OP;  // Zbb
            SH1ADD, SH2ADD, SH3ADD:                                 kind_enc = KIND_OP;  // Zba
            FENCE:                                                  kind_enc = KIND_FENCE;
            ECALL:                                                  kind_enc = KIND_ECALL;
            EBREAK:                                                 kind_enc = KIND_EBREAK;
            CSRRW, CSRRS, CSRRC, CSRRWI, CSRRSI, CSRRCI:             kind_enc = KIND_CSR;
            MUL, MULH, MULHSU, MULHU, DIV, DIVU, REM, REMU:         kind_enc = KIND_MULDIV;
            SEXT_B, SEXT_H, ZEXT_H_RV32, ORC_B, REV8_RV32:          kind_enc = KIND_BITMANIP;
            CLZ, CTZ, CPOP:                                         kind_enc = KIND_BITMANIP;
            LR_W:                                                   kind_enc = KIND_LR;
            SC_W:                                                   kind_enc = KIND_SC;
            AMOADD_W, AMOSWAP_W, AMOXOR_W, AMOOR_W, AMOAND_W:       kind_enc = KIND_AMO;
            AMOMIN_W, AMOMAX_W, AMOMINU_W, AMOMAXU_W:               kind_enc = KIND_AMO;
            CBO_CLEAN, CBO_FLUSH, CBO_INVAL:                        kind_enc = KIND_CBO;
            FMADD_S, FMSUB_S, FNMSUB_S, FNMADD_S:                   kind_enc = KIND_FP;
            FADD_S, FSUB_S, FMUL_S, FDIV_S, FSQRT_S:                kind_enc = KIND_FP;
            FSGNJ_S, FSGNJN_S, FSGNJX_S, FMIN_S, FMAX_S:            kind_enc = KIND_FP;
            FEQ_S, FLT_S, FLE_S, FCLASS_S:                          kind_enc = KIND_FP;
            FCVT_W_S, FCVT_WU_S, FCVT_S_W, FCVT_S_WU:               kind_enc = KIND_FP;
            MRET:                                                   kind_enc = KIND_MRET;
            WFI:                                                    kind_enc = KIND_WFI;
            default:                                                kind_enc = KIND_ILLEGAL;
        endcase

    // The instruction seen in every format.
    insn_fmt_t f;
    assign f.word = insn;

    // An F instruction (Zfinx): its unit and operation, by the encodings; the rm field of
    // one that rounds may be reserved (RiscvPkg), then it is illegal.
    fp_ctrl_t fp;
    assign fp   = fp_of(insn);
    assign kind = (kind_enc == KIND_FP && fp.uses_rm && rm_reserved(f.r.funct3))
                  ? KIND_ILLEGAL : kind_enc;

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
            LR_W[6:0]:            imm = '0;                 // AMO: the address is rs1
            CBO_INVAL[6:0]:       imm = '0;                 // MISC-MEM: a CBO's address
                                                            // is rs1 (FENCE: no imm)
            default:              imm = imm_i_of(insn);     // JALR, loads, OP-IMM
        endcase

    // @kb: rtl/design/mig3/interlock_by_opcode
    // The registers the interlock checks (hz_rs1, hz_rs2), by the opcode alone, not by kind,
    // the match of all encodings, which grows with every extension: the load-use check is
    // on ID's path. They may claim a read that does not happen (an immediate in an rs
    // field: CSRRWI, FCVT.S.WU's rs2 field; an illegal instruction), never miss one: LUI,
    // AUIPC, JAL read nothing; branches, stores, OP (also M, Zba, Zbb), AMO and F (OP-FP,
    // the R4 forms) rs1 and rs2; all others rs1. Opcodes from the encodings.
    logic hz1;          // may read rs1
    logic hz2;          // may read rs2
    always_comb
        case (f.r.opcode)
            LUI[6:0], AUIPC[6:0], JAL[6:0]:                      {hz1, hz2} = 2'b00;
            BEQ[6:0], SW[6:0], ADD[6:0], LR_W[6:0], FADD_S[6:0],
            FMADD_S[6:0], FMSUB_S[6:0], FNMSUB_S[6:0], FNMADD_S[6:0]: {hz1, hz2} = 2'b11;
            default:                                             {hz1, hz2} = 2'b10;
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
    // The operation of Alu2 (Mig3Alu), by the encodings: OP and OP-IMM, also the Zbb that
    // reuse the ALU (ANDN, ORN, XNOR, MIN, MINU, MAX, MAXU, ROL, ROR, RORI) and Zba (SH1ADD,
    // SH2ADD, SH3ADD: a shifted into the adder); a + b for every
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
            SH1ADD:             return ALU2_SH1ADD;
            SH2ADD:             return ALU2_SH2ADD;
            SH3ADD:             return ALU2_SH3ADD;
            default:            return ALU2_ADD;    // ADD, ADDI and the address sums
        endcase
    endfunction

    // The operation of an AMO at the point of coherence (AtomicPkg: AXI5 AWATOP's values),
    // by the encodings. AMOAND clears the bits of ~rs2 (Mig3Lsu inverts the operand).
    // @kb: rtl/design/mig3/amo
    function automatic AtomicPkg::atop_t atop_of(insn_t w);
        casez (w)
            AMOADD_W:  return AtomicPkg::ATOP_LD_ADD;
            AMOAND_W:  return AtomicPkg::ATOP_LD_CLR;
            AMOXOR_W:  return AtomicPkg::ATOP_LD_EOR;
            AMOOR_W:   return AtomicPkg::ATOP_LD_SET;
            AMOMIN_W:  return AtomicPkg::ATOP_LD_SMIN;
            AMOMAX_W:  return AtomicPkg::ATOP_LD_SMAX;
            AMOMINU_W: return AtomicPkg::ATOP_LD_UMIN;
            AMOMAXU_W: return AtomicPkg::ATOP_LD_UMAX;
            AMOSWAP_W: return AtomicPkg::ATOP_SWAP;
            default:   return AtomicPkg::ATOP_NONE;
        endcase
    endfunction

    // The operation of a CBO on the cache block of rs1 (CachePkg), by the encodings:
    // Mig3Lsu sends it as a store of no bytes.
    // @kb: rtl/design/mig3/cbo
    function automatic CachePkg::cmo_t cmo_of(insn_t w);
        casez (w)
            CBO_CLEAN: return CachePkg::CMO_CLEAN;
            CBO_FLUSH: return CachePkg::CMO_FLUSH;
            CBO_INVAL: return CachePkg::CMO_INVAL;
            default:   return CachePkg::CMO_NONE;
        endcase
    endfunction

    // @kb: rtl/design/mig3/fp_decode
    // An F instruction's FPU unit and operation, by the encodings (Zfinx); 0 for others.
    function automatic fp_ctrl_t fp_of(insn_t w);
        fp_ctrl_t c;
        c         = '0;
        c.en      = 1'b1;
        c.uses_rm = 1'b1;
        c.rm      = w[14:12];
        casez (w)
            FMADD_S:   begin c.unit = FPU_FMA;  c.fma_op = FpPkg::FMA_MADD;  end
            FMSUB_S:   begin c.unit = FPU_FMA;  c.fma_op = FpPkg::FMA_MSUB;  end
            FNMSUB_S:  begin c.unit = FPU_FMA;  c.fma_op = FpPkg::FMA_NMSUB; end
            FNMADD_S:  begin c.unit = FPU_FMA;  c.fma_op = FpPkg::FMA_NMADD; end
            FADD_S:    begin c.unit = FPU_FMA;  c.fma_op = FpPkg::FMA_ADD;   end
            FSUB_S:    begin c.unit = FPU_FMA;  c.fma_op = FpPkg::FMA_SUB;   end
            FMUL_S:    begin c.unit = FPU_FMA;  c.fma_op = FpPkg::FMA_MUL;   end
            FDIV_S:    c.unit = FPU_DIV_SQRT;
            FSQRT_S:   begin c.unit = FPU_DIV_SQRT;  c.sqrt = 1'b1; end
            FCVT_W_S:  c.unit = FPU_TO_INT;
            FCVT_WU_S: begin c.unit = FPU_TO_INT;  c.is_unsigned = 1'b1; end
            FCVT_S_W:  c.unit = FPU_FROM_INT;
            FCVT_S_WU: begin c.unit = FPU_FROM_INT;  c.is_unsigned = 1'b1; end
            // No rm field: funct3 selects the operation.
            FSGNJ_S:   begin c.unit = FPU_SGNJ;  c.sgnj = FpPkg::SGNJ_COPY;  c.uses_rm = 1'b0; end
            FSGNJN_S:  begin c.unit = FPU_SGNJ;  c.sgnj = FpPkg::SGNJ_NEG;   c.uses_rm = 1'b0; end
            FSGNJX_S:  begin c.unit = FPU_SGNJ;  c.sgnj = FpPkg::SGNJ_XOR;   c.uses_rm = 1'b0; end
            FMIN_S:    begin c.unit = FPU_MIN_MAX;  c.uses_rm = 1'b0; end
            FMAX_S:    begin c.unit = FPU_MIN_MAX;  c.max = 1'b1;  c.uses_rm = 1'b0; end
            FEQ_S:     begin c.unit = FPU_CMP;  c.cmp = FP_CMP_EQ;  c.uses_rm = 1'b0; end
            FLT_S:     begin c.unit = FPU_CMP;  c.cmp = FP_CMP_LT;  c.uses_rm = 1'b0; end
            FLE_S:     begin c.unit = FPU_CMP;  c.cmp = FP_CMP_LE;  c.uses_rm = 1'b0; end
            FCLASS_S:  begin c.unit = FPU_CLASS;  c.uses_rm = 1'b0; end
            default:   c = '0;
        endcase
        return c;
    endfunction

    // Registers an F instruction reads besides rs1: {rs2, rs3}; R4 reads both, a
    // conversion, FSQRT.S and FCLASS.S neither.
    function automatic logic [1:0] fp_regs_of(insn_t w);
        casez (w)
            FMADD_S, FMSUB_S, FNMSUB_S, FNMADD_S:                    return 2'b11;
            FSQRT_S, FCLASS_S, FCVT_W_S, FCVT_WU_S, FCVT_S_W, FCVT_S_WU: return 2'b00;
            default:                                                 return 2'b10;
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
        dec.rs3    = f.r4.rs3;
        dec.hz_rs1 = hz1;
        dec.hz_rs2 = hz2;
        dec.funct3 = f.r.funct3;
        dec.alt    = alt_of(insn);     // insn[30]: SUB, SRA, SRAI

        // Per kind: registers written and read, source of rd, format of the immediate,
        // controls of the parts. Defaults: nothing written or read, I-type immediate,
        // ALU adds rs1 + imm, no other control.
        dec.rd_we    = 1'b0;
        dec.rd_src   = RD_ALU;
        dec.uses_rs1 = 1'b0;
        dec.uses_rs2 = 1'b0;
        dec.uses_rs3 = 1'b0;
        dec.imm      = imm;              // by opcode (shifts: imm[4:0] is shamt)
        dec.alu      = '{a: A_RS1, b_imm: 1'b1, alu2: ctrl_of(alu_op_of(insn))};
        dec.br       = '0;
        dec.mem      = '0;
        dec.atomic   = '0;
        dec.sys      = '0;
        dec.muldiv   = '0;
        dec.fp       = '0;
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
            KIND_LR: begin
                dec.rd_we = 1'b1;  dec.rd_src = RD_LOAD;  dec.uses_rs1 = 1'b1;  dec.mem.read = 1'b1;
                dec.atomic.lr = 1'b1;
            end
            KIND_SC: begin
                dec.rd_we = 1'b1;  dec.rd_src = RD_ATOMIC;
                dec.uses_rs1 = 1'b1;  dec.uses_rs2 = 1'b1;  dec.mem.write = 1'b1;
                dec.atomic.sc = 1'b1;
            end
            KIND_AMO: begin
                dec.rd_we = 1'b1;  dec.rd_src = RD_LOAD;
                dec.uses_rs1 = 1'b1;  dec.uses_rs2 = 1'b1;  dec.mem.read = 1'b1;
                dec.atomic.atop = atop_of(insn);
            end
            KIND_CBO: begin
                dec.uses_rs1 = 1'b1;  dec.mem.write = 1'b1;  dec.mem.cmo = cmo_of(insn);
            end
            KIND_FP: begin
                dec.rd_we = 1'b1;  dec.rd_src = RD_FP;  dec.uses_rs1 = 1'b1;
                {dec.uses_rs2, dec.uses_rs3} = fp_regs_of(insn);
                dec.fp = fp;
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
            KIND_WFI:     dec.sys.wfi     = 1'b1;
            KIND_EBREAK:  dec.sys.ebreak  = 1'b1;
            KIND_MRET:    dec.sys.mret    = 1'b1;
            KIND_ILLEGAL: dec.sys.illegal = 1'b1;
            default: ;  // FENCE: a no-op
        endcase
    end

endmodule

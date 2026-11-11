/* Unit test of Mig3Decode.
 *
 * decode.S lists instructions encoded by the assembler, each with its expected
 * decode (see decode.S). For every case the instruction goes to Mig3Decode and the
 * fields that mean something for its kind are compared: kind always; the control
 * groups br, mem, sys, muldiv and bitmanip always and alu for kinds that use the ALU,
 * each against a model of its own in this file; for legal instructions rd_we, uses_rs1 and
 * uses_rs2, then rd and rd_src when rd_we (rd_src expected from the kind: LINK for JAL
 * and JALR, LOAD for loads, CSR for CSR instructions, MULDIV for M, BITMANIP for the Zbb
 * of ComputeCoreBitmanip, else ALU), rs1
 * when uses_rs1, rs2 when uses_rs2, funct3 when the kind has it, alt for OP and OP-IMM
 * shifts, imm when the kind has an immediate (the CSR address for CSR instructions).
 * LR.W and SC.W: a load and a store with imm 0 and their atomic controls, rd_src LOAD and
 * ATOMIC. An AMO: a load of rs1 to rd (imm 0) that reads rs2, its atop by its encoding.
 * A CBO: a store of rs1 (imm 0) that reads no rs2, its cmo by its encoding. An F
 * instruction (Zfinx): rd_src FP, the rm field in funct3, its FPU controls against a
 * model by opcode, funct5 and funct3 (fp_model), uses_rs3 for the R4 forms and rs3 (the
 * case's imm column).
 * At the end every kind must have had a case; KIND_BITMANIP only with +zbb, KIND_CBO only
 * with +zicbom, KIND_FP only with +zfinx (their cases need a compiler that knows Zbb,
 * Zicbom, Zfinx).
 * Loads +hex=<file> into a SimROM and reads it with peek().
 * Stops at the first mismatch with $fatal.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module TbMig3Decode;
    import Mig3Pkg::*;
    import RiscvPkg::*;
    import RiscvInstrPkg::*;    // the encodings, for the models of the ALU operation

    localparam AW     = MIG3_CFG.mem_addr_width;
    localparam FIELDS = 10;                  // expected values after the instruction
    localparam CASE   = 4 * (1 + FIELDS);    // bytes of one case

    // Cases are read with peek(), the read port is not used.
    /* verilator lint_off UNUSEDSIGNAL */
    word_t       rom_data;
    /* verilator lint_on UNUSEDSIGNAL */
    insn_t       insn;
    decoded_t    dec;

    string       hex;
    integer      n;
    integer      c;
    integer      k;
    integer      addr;
    // Expected: kind, rd_we, uses_rs1, uses_rs2, rd, rs1, rs2, funct3, alt, imm.
    word_t       e [FIELDS];
    kind_e       exp_kind;    // kind expected, from the case file
    kind_e       last_kind;   // kinds up to it must have had a case
    logic [31:0] tested;      // tested[k]: kind k had a case

    SimROM #(.DATA_SIZE(4), .ADDR_WIDTH(AW)) u_cases(
        .clk(1'b0), .en(1'b0), .addr('0), .data(rom_data));

    Mig3Decode u_mig3_decode(.insn, .dec);

    // Word at byte address a, little-endian.
    function automatic word_t word(input integer a);
        // Only the AW low bits of the address reach the memory.
        /* verilator lint_off UNUSEDSIGNAL */
        integer ab;
        /* verilator lint_on UNUSEDSIGNAL */
        for (int b = 0; b < 4; b++) begin
            ab = a + b;
            word[8*b +: 8] = u_cases.peek(ab[AW-1:0]);
        end
    endfunction

    // Kinds that have funct3, and kinds that have an immediate.
    function automatic logic has_funct3(input kind_e kind);
        case (kind)
            KIND_JALR, KIND_BRANCH, KIND_LOAD, KIND_STORE, KIND_OP_IMM, KIND_OP,
            KIND_FENCE, KIND_CSR, KIND_MULDIV, KIND_LR, KIND_SC, KIND_AMO, KIND_CBO,
            KIND_FP:
                return 1'b1;
            default:
                return 1'b0;
        endcase
    endfunction

    function automatic logic has_imm(input kind_e kind);
        case (kind)
            KIND_LUI, KIND_AUIPC, KIND_JAL, KIND_JALR, KIND_BRANCH, KIND_LOAD, KIND_STORE,
            KIND_OP_IMM, KIND_CSR, KIND_LR, KIND_SC, KIND_AMO, KIND_CBO:
                return 1'b1;
            default:
                return 1'b0;
        endcase
    endfunction

    // Instructions with alt (insn[30]): OP (SUB, SRA) and the OP-IMM shifts (SRAI).
    function automatic logic has_alt(input kind_e kind, input funct3_t f3);
        return kind == KIND_OP || (kind == KIND_OP_IMM && (f3 == F3_SLL || f3 == F3_SRL_SRA));
    endfunction

    // Source of rd expected for a kind that writes rd.
    function automatic rd_src_e rd_src_of(input kind_e kind);
        case (kind)
            KIND_JAL, KIND_JALR: return RD_LINK;
            KIND_LOAD, KIND_LR, KIND_AMO: return RD_LOAD;
            KIND_SC:             return RD_ATOMIC;
            KIND_FP:             return RD_FP;
            KIND_CSR:            return RD_CSR;
            KIND_MULDIV:         return RD_MULDIV;
            KIND_BITMANIP:       return RD_BITMANIP;
            default:             return RD_ALU;
        endcase
    endfunction

    // Controls expected for a kind: a model of its own, not a copy of Mig3Decode's table.
    function automatic logic uses_alu(input kind_e kind);
        case (kind)
            KIND_LUI, KIND_AUIPC, KIND_LOAD, KIND_STORE, KIND_OP_IMM, KIND_OP,
            KIND_LR, KIND_SC, KIND_AMO, KIND_CBO:   // the address rs1 + 0
                return 1'b1;
            default:
                return 1'b0;
        endcase
    endfunction

    // The operation of Alu2 for an instruction, by its encoding (RiscvInstrPkg); a + b for
    // the instructions that are not OP or OP-IMM.
    function automatic Alu2Pkg::op_e alu_op_of(input insn_t w);
        if (w ==? SUB)                         return Alu2Pkg::ALU2_SUB;
        if (w ==? SLL  || w ==? SLLI)          return Alu2Pkg::ALU2_SLL;
        if (w ==? SLT  || w ==? SLTI)          return Alu2Pkg::ALU2_SLT;
        if (w ==? SLTU || w ==? SLTIU)         return Alu2Pkg::ALU2_SLTU;
        if (w ==? XOR  || w ==? XORI)          return Alu2Pkg::ALU2_XOR;
        if (w ==? SRL  || w ==? SRLI)          return Alu2Pkg::ALU2_SRL;
        if (w ==? SRA  || w ==? SRAI)          return Alu2Pkg::ALU2_SRA;
        if (w ==? OR   || w ==? ORI)           return Alu2Pkg::ALU2_OR;
        if (w ==? AND  || w ==? ANDI)          return Alu2Pkg::ALU2_AND;
        if (w ==? ANDN)                        return Alu2Pkg::ALU2_ANDN;
        if (w ==? ORN)                         return Alu2Pkg::ALU2_ORN;
        if (w ==? XNOR)                        return Alu2Pkg::ALU2_XNOR;
        if (w ==? MIN)                         return Alu2Pkg::ALU2_MIN;
        if (w ==? MINU)                        return Alu2Pkg::ALU2_MINU;
        if (w ==? MAX)                         return Alu2Pkg::ALU2_MAX;
        if (w ==? MAXU)                        return Alu2Pkg::ALU2_MAXU;
        if (w ==? ROL)                         return Alu2Pkg::ALU2_ROL;
        if (w ==? SH1ADD)                      return Alu2Pkg::ALU2_SH1ADD;
        if (w ==? SH2ADD)                      return Alu2Pkg::ALU2_SH2ADD;
        if (w ==? SH3ADD)                      return Alu2Pkg::ALU2_SH3ADD;
        if (w ==? ROR  || w ==? RORI_RV32)     return Alu2Pkg::ALU2_ROR;
        return Alu2Pkg::ALU2_ADD;
    endfunction

    // The interlock's reads by the opcode (Mig3Decode hz_rs1, hz_rs2): {rs1, rs2}. The rule
    // as written down; that it covers every real read, Mig3Control's a_hz_covers_uses checks.
    function automatic logic [1:0] hz_model(input logic [6:0] opcode);
        logic hz1;
        logic hz2;
        case (opcode)
            LUI[6:0], AUIPC[6:0], JAL[6:0]:                      {hz1, hz2} = 2'b00;
            BEQ[6:0], SW[6:0], ADD[6:0], LR_W[6:0], FADD_S[6:0],
            FMADD_S[6:0], FMSUB_S[6:0], FNMSUB_S[6:0], FNMADD_S[6:0]: {hz1, hz2} = 2'b11;
            default:                                             {hz1, hz2} = 2'b10;
        endcase
        return {hz1, hz2};
    endfunction

    // ALU controls expected: the operands of the kind, the controls of the operation.
    function automatic alu_ctrl_t alu_of(input kind_e kind, input insn_t w);
        alu_ctrl_t ctrl;
        ctrl.a     = A_RS1;
        ctrl.b_imm = 1'b1;
        ctrl.alu2  = Alu2Pkg::ctrl_of(alu_op_of(w));
        case (kind)
            KIND_LUI:   ctrl.a = A_ZERO;
            KIND_AUIPC: ctrl.a = A_PC;
            KIND_OP:    ctrl.b_imm = 1'b0;
            default: ;
        endcase
        return ctrl;
    endfunction

    // The operation of ComputeCoreBitmanip, by the encodings (RiscvInstrPkg); 0 for other
    // kinds.
    function automatic ComputeCoreBitmanipPkg::bm_op_e bitmanip_of(input kind_e kind,
                                                                   input insn_t w);
        if (kind == KIND_BITMANIP) begin
            if (w ==? RiscvInstrPkg::SEXT_B)      return ComputeCoreBitmanipPkg::BM_SEXT_B;
            if (w ==? RiscvInstrPkg::SEXT_H)      return ComputeCoreBitmanipPkg::BM_SEXT_H;
            if (w ==? RiscvInstrPkg::ZEXT_H_RV32) return ComputeCoreBitmanipPkg::BM_ZEXT_H;
            if (w ==? RiscvInstrPkg::ORC_B)       return ComputeCoreBitmanipPkg::BM_ORC_B;
            if (w ==? RiscvInstrPkg::REV8_RV32)   return ComputeCoreBitmanipPkg::BM_REV8;
            if (w ==? RiscvInstrPkg::CLZ)         return ComputeCoreBitmanipPkg::BM_CLZ;
            if (w ==? RiscvInstrPkg::CTZ)         return ComputeCoreBitmanipPkg::BM_CTZ;
            if (w ==? RiscvInstrPkg::CPOP)        return ComputeCoreBitmanipPkg::BM_CPOP;
        end
        return ComputeCoreBitmanipPkg::bm_op_e'('0);
    endfunction

    // JALR is a return (pops the return-address stack) when rs1 is x1 or x5, unless rd = rs1.
    function automatic logic is_return(input reg_id_t rd, input reg_id_t rs1);
        logic rd_link;
        logic rs1_link;
        rd_link  = rd == 5'd1 || rd == 5'd5;
        rs1_link = rs1 == 5'd1 || rs1 == 5'd5;
        return rs1_link && !(rd_link && rd == rs1);
    endfunction

    // JAL or JALR is a call (pushes the return-address stack) when rd is x1 or x5.
    function automatic logic is_call(input reg_id_t rd);
        return rd == 5'd1 || rd == 5'd5;
    endfunction

    function automatic br_ctrl_t br_of(input kind_e kind, input reg_id_t rd, input reg_id_t rs1);
        case (kind)
            KIND_JAL:    return '{jump: 1'b1, branch: 1'b0, target_rs1: 1'b0, ret: 1'b0,
                                  call: is_call(rd)};
            KIND_JALR:   return '{jump: 1'b1, branch: 1'b0, target_rs1: 1'b1,
                                  ret: is_return(rd, rs1), call: is_call(rd)};
            KIND_BRANCH: return '{jump: 1'b0, branch: 1'b1, target_rs1: 1'b0, ret: 1'b0,
                                  call: 1'b0};
            default:     return '0;
        endcase
    endfunction

    // The operation of a CBO by its encoding.
    function automatic CachePkg::cmo_t cmo_model(input insn_t w);
        if (w ==? CBO_CLEAN) return CachePkg::CMO_CLEAN;
        if (w ==? CBO_FLUSH) return CachePkg::CMO_FLUSH;
        if (w ==? CBO_INVAL) return CachePkg::CMO_INVAL;
        return CachePkg::CMO_NONE;
    endfunction

    function automatic mem_ctrl_t mem_of(input kind_e kind, input insn_t w);
        return '{read: kind == KIND_LOAD || kind == KIND_LR || kind == KIND_AMO,
                 write: kind == KIND_STORE || kind == KIND_SC || kind == KIND_CBO,
                 cmo: kind == KIND_CBO ? cmo_model(w) : CachePkg::CMO_NONE};
    endfunction

    // The operation of an AMO by its encoding (AMOAND: a clear of ~rs2).
    function automatic AtomicPkg::atop_t atop_model(input insn_t w);
        if (w ==? AMOADD_W)  return AtomicPkg::ATOP_LD_ADD;
        if (w ==? AMOAND_W)  return AtomicPkg::ATOP_LD_CLR;
        if (w ==? AMOXOR_W)  return AtomicPkg::ATOP_LD_EOR;
        if (w ==? AMOOR_W)   return AtomicPkg::ATOP_LD_SET;
        if (w ==? AMOMIN_W)  return AtomicPkg::ATOP_LD_SMIN;
        if (w ==? AMOMAX_W)  return AtomicPkg::ATOP_LD_SMAX;
        if (w ==? AMOMINU_W) return AtomicPkg::ATOP_LD_UMIN;
        if (w ==? AMOMAXU_W) return AtomicPkg::ATOP_LD_UMAX;
        if (w ==? AMOSWAP_W) return AtomicPkg::ATOP_SWAP;
        return AtomicPkg::ATOP_NONE;
    endfunction

    function automatic atomic_ctrl_t atomic_of(input kind_e kind, input insn_t w);
        return '{lr: kind == KIND_LR, sc: kind == KIND_SC,
                 atop: kind == KIND_AMO ? atop_model(w) : AtomicPkg::ATOP_NONE};
    endfunction

    function automatic sys_ctrl_t sys_of(input kind_e kind);
        return '{csr: kind == KIND_CSR, mret: kind == KIND_MRET, ecall: kind == KIND_ECALL,
                 ebreak: kind == KIND_EBREAK, illegal: kind == KIND_ILLEGAL,
                 wfi: kind == KIND_WFI};
    endfunction

    // M controls expected, by the encodings of the instructions (RiscvInstrPkg).
    function automatic muldiv_ctrl_t muldiv_of(input kind_e kind, input insn_t w);
        logic div;
        logic rem;
        if (kind != KIND_MULDIV)
            return '0;
        rem = w ==? RiscvInstrPkg::REM || w ==? RiscvInstrPkg::REMU;
        div = w ==? RiscvInstrPkg::DIV || w ==? RiscvInstrPkg::DIVU || rem;
        return '{en: 1'b1, div: div, rem: rem, mul_lo: w ==? RiscvInstrPkg::MUL,
                 a_signed: w ==? RiscvInstrPkg::MULH || w ==? RiscvInstrPkg::MULHSU,
                 b_signed: w ==? RiscvInstrPkg::MULH,
                 div_signed: w ==? RiscvInstrPkg::DIV || w ==? RiscvInstrPkg::REM};
    endfunction

    // An F instruction's FPU controls (Zfinx), by its opcode, funct5 (bits 31..27) and funct3
    // as the encodings have them; 0 for other kinds.
    // Only the opcode, funct5, funct3 and bit 20 (the .WU forms) of w are used.
    /* verilator lint_off UNUSEDSIGNAL */
    function automatic fp_ctrl_t fp_model(input kind_e kind, input insn_t w);
        fp_ctrl_t fc;
        fc = '0;
        if (kind != KIND_FP)
            return fc;
        fc.en      = 1'b1;
        fc.rm      = w[14:12];
        fc.uses_rm = 1'b1;
        if (w[6:0] != FADD_S[6:0]) begin          // R4: the opcode is the operation
            fc.unit   = FPU_FMA;
            fc.fma_op = w[6:0] == FMADD_S[6:0] ? FpPkg::FMA_MADD :
                       w[6:0] == FMSUB_S[6:0] ? FpPkg::FMA_MSUB :
                       w[6:0] == FNMSUB_S[6:0] ? FpPkg::FMA_NMSUB : FpPkg::FMA_NMADD;
            return fc;
        end
        case (w[31:27])
            FADD_S[31:27]:   begin fc.unit = FPU_FMA;  fc.fma_op = FpPkg::FMA_ADD; end
            FSUB_S[31:27]:   begin fc.unit = FPU_FMA;  fc.fma_op = FpPkg::FMA_SUB; end
            FMUL_S[31:27]:   begin fc.unit = FPU_FMA;  fc.fma_op = FpPkg::FMA_MUL; end
            FDIV_S[31:27]:   fc.unit = FPU_DIV_SQRT;
            FSQRT_S[31:27]:  begin fc.unit = FPU_DIV_SQRT;  fc.sqrt = 1'b1; end
            FCVT_W_S[31:27]: begin fc.unit = FPU_TO_INT;  fc.is_unsigned = w[20]; end
            FCVT_S_W[31:27]: begin fc.unit = FPU_FROM_INT;  fc.is_unsigned = w[20]; end
            FSGNJ_S[31:27]: begin
                fc.unit    = FPU_SGNJ;
                fc.uses_rm = 1'b0;
                fc.sgnj    = w[13] ? FpPkg::SGNJ_XOR : w[12] ? FpPkg::SGNJ_NEG
                                                     : FpPkg::SGNJ_COPY;
            end
            FMIN_S[31:27]: begin
                fc.unit    = FPU_MIN_MAX;
                fc.max     = w[12];
                fc.uses_rm = 1'b0;
            end
            FEQ_S[31:27]: begin
                fc.unit    = FPU_CMP;
                fc.uses_rm = 1'b0;
                fc.cmp     = w[13] ? FP_CMP_EQ : w[12] ? FP_CMP_LT : FP_CMP_LE;
            end
            default:         begin fc.unit = FPU_CLASS;  fc.uses_rm = 1'b0; end  // FCLASS.S
        endcase
        return fc;
    endfunction
    /* verilator lint_on UNUSEDSIGNAL */

    // Compare one field of case cn with instruction w.
    task automatic check(input integer cn, input insn_t w, input string field, input word_t got,
                         input word_t exp);
        if (got !== exp)
            $fatal(1, "Mig3Decode case %0d, insn %h: %s got %h, expected %h",
                   cn, w, field, got, exp);
    endtask

    initial begin
        if (!$value$plusargs("hex=%s", hex))
            $fatal(1, "Mig3Decode: plusarg +hex=<file> is missing");
        if (u_cases.load(hex, u_cases.VLOG_HEX_FORMAT) != 1)
            $fatal(1, "Mig3Decode: load() of %s returned 0", hex);

        tested = '0;
        n = word(0);
        for (c = 0; c < n; c = c + 1) begin
            addr = 4 + c * CASE;
            insn = word(addr);
            for (k = 0; k < FIELDS; k = k + 1)
                e[k] = word(addr + 4 + 4 * k);
            exp_kind = kind_e'(e[0][4:0]);
            #1;
            check(c, insn, "kind",   32'(dec.kind),   e[0]);
            check(c, insn, "br",     32'(dec.br),     32'(br_of(exp_kind, e[4][4:0], e[5][4:0])));
            check(c, insn, "mem",    32'(dec.mem),    32'(mem_of(exp_kind, insn)));
            check(c, insn, "atomic", 32'(dec.atomic), 32'(atomic_of(exp_kind, insn)));
            check(c, insn, "sys",    32'(dec.sys),    32'(sys_of(exp_kind)));
            check(c, insn, "muldiv", 32'(dec.muldiv), 32'(muldiv_of(exp_kind, insn)));
            check(c, insn, "bitmanip", 32'(dec.bitmanip), 32'(bitmanip_of(exp_kind, insn)));
            check(c, insn, "fp",     32'(dec.fp),     32'(fp_model(exp_kind, insn)));
            check(c, insn, "hz_rs1", 32'(dec.hz_rs1), 32'(hz_model(insn[6:0]) >> 1));
            check(c, insn, "hz_rs2", 32'(dec.hz_rs2), 32'(hz_model(insn[6:0]) & 2'b01));
            check(c, insn, "uses_rs3", 32'(dec.uses_rs3),
                  32'(exp_kind == KIND_FP && insn[6:0] != FADD_S[6:0]));
            if (dec.uses_rs3)
                check(c, insn, "rs3", 32'(dec.rs3), e[9]);
            if (uses_alu(exp_kind))
                check(c, insn, "alu", 32'(dec.alu), 32'(alu_of(exp_kind, insn)));
            if (exp_kind != KIND_ILLEGAL) begin
                check(c, insn, "rd_we",    32'(dec.rd_we),    e[1]);
                check(c, insn, "uses_rs1", 32'(dec.uses_rs1), e[2]);
                check(c, insn, "uses_rs2", 32'(dec.uses_rs2), e[3]);
                if (e[1][0]) begin
                    check(c, insn, "rd",     32'(dec.rd),     e[4]);
                    check(c, insn, "rd_src", 32'(dec.rd_src), 32'(rd_src_of(exp_kind)));
                end
                if (e[2][0])
                    check(c, insn, "rs1", 32'(dec.rs1), e[5]);
                if (e[3][0])
                    check(c, insn, "rs2", 32'(dec.rs2), e[6]);
                if (has_funct3(exp_kind))
                    check(c, insn, "funct3", 32'(dec.funct3), e[7]);
                if (has_alt(exp_kind, e[7][2:0]))
                    check(c, insn, "alt", 32'(dec.alt), e[8]);
                if (has_imm(exp_kind))
                    check(c, insn, "imm", dec.imm, e[9]);
            end
            tested[exp_kind] = 1'b1;
        end

        last_kind = KIND_FP;
        for (k = 0; k <= last_kind; k = k + 1)
            if (!tested[k] && !(k == int'(KIND_BITMANIP) && !$test$plusargs("zbb")) &&
                !(k == int'(KIND_CBO) && !$test$plusargs("zicbom")) &&
                !(k == int'(KIND_FP) && !$test$plusargs("zfinx")))
                $fatal(1, "Mig3Decode: no case of kind %0d", k);
        $display("PASS: %0d cases", n);
        $finish;
    end
endmodule

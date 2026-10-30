/* Unit test of Mig2Decode.
 *
 * decode.S lists instructions encoded by the assembler, each with its expected
 * decode (see decode.S). For every case the instruction goes to Mig2Decode and the
 * fields that mean something for its kind are compared: kind always; the control
 * groups br, mem, sys, muldiv and bitmanip always and alu for kinds that use the ALU,
 * each against a model of its own in this file; for legal instructions rd_we, uses_rs1 and
 * uses_rs2, then rd and rd_src when rd_we (rd_src expected from the kind: LINK for JAL
 * and JALR, LOAD for loads, CSR for CSR instructions, MULDIV for M, BITMANIP for the Zbb
 * of ComputeCoreBitmanip, else ALU), rs1
 * when uses_rs1, rs2 when uses_rs2, funct3 when the kind has it, alt for OP and OP-IMM
 * shifts, imm when the kind has an immediate (the CSR address for CSR instructions).
 * At the end every kind must have had a case; KIND_BITMANIP only with +zbb (its cases
 * need a compiler that knows Zbb).
 * Loads +hex=<file> into a SimROM and reads it with peek().
 * Stops at the first mismatch with $fatal.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module TbMig2Decode;
    import Mig2Pkg::*;
    import RiscvPkg::*;
    import RiscvInstrPkg::*;    // the encodings, for the models of the ALU operation

    localparam AW     = MIG2_CFG.mem_addr_width;
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

    Mig2Decode u_mig2_decode(.insn, .dec);

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
            KIND_FENCE, KIND_CSR, KIND_MULDIV:
                return 1'b1;
            default:
                return 1'b0;
        endcase
    endfunction

    function automatic logic has_imm(input kind_e kind);
        case (kind)
            KIND_LUI, KIND_AUIPC, KIND_JAL, KIND_JALR, KIND_BRANCH, KIND_LOAD, KIND_STORE,
            KIND_OP_IMM, KIND_CSR:
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
            KIND_LOAD:           return RD_LOAD;
            KIND_CSR:            return RD_CSR;
            KIND_MULDIV:         return RD_MULDIV;
            KIND_BITMANIP:       return RD_BITMANIP;
            default:             return RD_ALU;
        endcase
    endfunction

    // Controls expected for a kind: a model of its own, not a copy of Mig2Decode's table.
    function automatic logic uses_alu(input kind_e kind);
        case (kind)
            KIND_LUI, KIND_AUIPC, KIND_LOAD, KIND_STORE, KIND_OP_IMM, KIND_OP: return 1'b1;
            default:                                                         return 1'b0;
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
        if (w ==? ROR  || w ==? RORI_RV32)     return Alu2Pkg::ALU2_ROR;
        return Alu2Pkg::ALU2_ADD;
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

    function automatic mem_ctrl_t mem_of(input kind_e kind);
        return '{read: kind == KIND_LOAD, write: kind == KIND_STORE};
    endfunction

    function automatic sys_ctrl_t sys_of(input kind_e kind);
        return '{csr: kind == KIND_CSR, mret: kind == KIND_MRET, ecall: kind == KIND_ECALL,
                 ebreak: kind == KIND_EBREAK, illegal: kind == KIND_ILLEGAL};
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

    // Compare one field of case cn with instruction w.
    task automatic check(input integer cn, input insn_t w, input string field, input word_t got,
                         input word_t exp);
        if (got !== exp)
            $fatal(1, "Mig2Decode case %0d, insn %h: %s got %h, expected %h",
                   cn, w, field, got, exp);
    endtask

    initial begin
        if (!$value$plusargs("hex=%s", hex))
            $fatal(1, "Mig2Decode: plusarg +hex=<file> is missing");
        if (u_cases.load(hex, u_cases.VLOG_HEX_FORMAT) != 1)
            $fatal(1, "Mig2Decode: load() of %s returned 0", hex);

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
            check(c, insn, "mem",    32'(dec.mem),    32'(mem_of(exp_kind)));
            check(c, insn, "sys",    32'(dec.sys),    32'(sys_of(exp_kind)));
            check(c, insn, "muldiv", 32'(dec.muldiv), 32'(muldiv_of(exp_kind, insn)));
            check(c, insn, "bitmanip", 32'(dec.bitmanip), 32'(bitmanip_of(exp_kind, insn)));
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

        last_kind = $test$plusargs("zbb") ? KIND_BITMANIP : KIND_MULDIV;
        for (k = 0; k <= last_kind; k = k + 1)
            if (!tested[k])
                $fatal(1, "Mig2Decode: no case of kind %0d", k);
        $display("PASS: %0d cases", n);
        $finish;
    end
endmodule

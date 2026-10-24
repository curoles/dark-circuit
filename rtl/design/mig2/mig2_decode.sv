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

    // CSR instructions: the CSR address, not sign-extended (0xc00 is not negative);
    // register forms read rs1, the I forms use the rs1 field as immediate.
    word_t imm_csr;
    logic  csr_reg;
    assign imm_csr = {{(WIDTH-12){1'b0}}, f.i.imm_11_0};
    assign csr_reg = f.i.funct3 == F3_CSRRW || f.i.funct3 == F3_CSRRS || f.i.funct3 == F3_CSRRC;

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

    // Link register of the return-address hints of JAL/JALR: x1 (ra) or x5 (t0).
    function automatic logic is_link(reg_id_t r);
        return r == 5'd1 || r == 5'd5;
    endfunction

    always_comb begin
        // Fields at the same place in every format.
        dec.kind   = kind;
        dec.rd     = f.r.rd;
        dec.rs1    = f.r.rs1;
        dec.rs2    = f.r.rs2;
        dec.funct3 = f.r.funct3;
        dec.alt    = f.r.funct7[5];    // insn[30]: SUB, SRA, SRAI

        // Per kind: registers written and read, source of rd, format of the immediate,
        // controls of the parts. Defaults: nothing written or read, I-type immediate,
        // ALU adds rs1 + imm, no other control.
        dec.rd_we    = 1'b0;
        dec.rd_src   = RD_ALU;
        dec.uses_rs1 = 1'b0;
        dec.uses_rs2 = 1'b0;
        dec.imm      = imm_i_of(insn);   // JALR, LOAD, OP_IMM (shifts: imm[4:0] is shamt)
        dec.alu      = '{a: A_RS1, b_imm: 1'b1, op: 1'b0, sub: 1'b0};
        dec.br       = '0;
        dec.mem      = '0;
        dec.sys      = '0;
        dec.muldiv   = '0;
        case (kind)
            KIND_LUI: begin
                dec.rd_we = 1'b1;  dec.imm = imm_u_of(insn);  dec.alu.a = A_ZERO;
            end
            KIND_AUIPC: begin
                dec.rd_we = 1'b1;  dec.imm = imm_u_of(insn);  dec.alu.a = A_PC;
            end
            KIND_JAL: begin
                dec.rd_we = 1'b1;  dec.rd_src = RD_LINK;  dec.imm = imm_j_of(insn);
                dec.br.jump = 1'b1;
            end
            KIND_JALR: begin
                dec.rd_we = 1'b1;  dec.rd_src = RD_LINK;  dec.uses_rs1 = 1'b1;
                dec.br.jump = 1'b1;  dec.br.target_rs1 = 1'b1;
                // A return pops the return-address stack: rs1 is a link, rd is not rs1.
                dec.br.ret = is_link(dec.rs1) && (!is_link(dec.rd) || dec.rd != dec.rs1);
            end
            KIND_BRANCH: begin
                dec.uses_rs1 = 1'b1;  dec.uses_rs2 = 1'b1;  dec.imm = imm_b_of(insn);
                dec.br.branch = 1'b1;
            end
            KIND_LOAD: begin
                dec.rd_we = 1'b1;  dec.rd_src = RD_LOAD;  dec.uses_rs1 = 1'b1;  dec.mem.read = 1'b1;
            end
            KIND_STORE: begin
                dec.uses_rs1 = 1'b1;  dec.uses_rs2 = 1'b1;  dec.imm = imm_s_of(insn);
                dec.mem.write = 1'b1;
            end
            KIND_OP_IMM: begin
                dec.rd_we = 1'b1;  dec.uses_rs1 = 1'b1;  dec.alu.op = 1'b1;
            end
            KIND_OP: begin
                dec.rd_we = 1'b1;  dec.uses_rs1 = 1'b1;  dec.uses_rs2 = 1'b1;
                dec.alu = '{a: A_RS1, b_imm: 1'b0, op: 1'b1, sub: dec.alt};
            end
            KIND_MULDIV: begin
                dec.rd_we = 1'b1;  dec.rd_src = RD_MULDIV;
                dec.uses_rs1 = 1'b1;  dec.uses_rs2 = 1'b1;  dec.muldiv = muldiv_of(dec.funct3);
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

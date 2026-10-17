/* Mig1 decode: instruction -> decoded_t, purely combinational.
 *
 * kind comes from exact match with the RISC-V encodings of RiscvInstrPkg
 * (generated from riscv-opcodes), so every other word is KIND_ILLEGAL.
 * Register numbers, funct3, alt and immediates come straight from instruction
 * fields (RiscvPkg formats), at the same place for every instruction; units
 * derive their controls from kind, funct3 and alt. Immediates are for RV32:
 * U-type is not sign-extended beyond 32 bits.
 */
module Mig1Decode import Mig1Pkg::*, RiscvPkg::*; (
    input  logic [INSN_WIDTH-1:0] insn,   // insn_t, see Mig1Pkg about ports
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

    // Fields at the same place in every format. Selected with assign, not in always_comb:
    // Icarus does not support constant selects there and warns.
    reg_addr_t  rd;
    reg_addr_t  rs1;
    reg_addr_t  rs2;
    logic [2:0] funct3;
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

        // Per kind: register written and read, format of the immediate.
        // Default: nothing written or read, I-type immediate.
        dec.rd_we    = 1'b0;
        dec.uses_rs1 = 1'b0;
        dec.uses_rs2 = 1'b0;
        dec.imm      = imm_i;         // JALR, LOAD, OP_IMM (shifts: imm[4:0] is shamt)
        case (kind)
            KIND_LUI, KIND_AUIPC:              begin dec.rd_we = 1'b1;                          dec.imm = imm_u; end
            KIND_JAL:                          begin dec.rd_we = 1'b1;                          dec.imm = imm_j; end
            KIND_JALR, KIND_LOAD, KIND_OP_IMM: begin dec.rd_we = 1'b1; dec.uses_rs1 = 1'b1;                      end
            KIND_OP:                           begin dec.rd_we = 1'b1; dec.uses_rs1 = 1'b1; dec.uses_rs2 = 1'b1; end
            KIND_BRANCH:                       begin dec.uses_rs1 = 1'b1; dec.uses_rs2 = 1'b1;  dec.imm = imm_b; end
            KIND_STORE:                        begin dec.uses_rs1 = 1'b1; dec.uses_rs2 = 1'b1;  dec.imm = imm_s; end
            default:                           ;  // FENCE, ECALL, EBREAK, ILLEGAL
        endcase
    end

endmodule

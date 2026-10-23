/* Mig2 branch unit: next pc of JAL, JALR and branches, and the link value,
 * purely combinational.
 *
 * branch.taken=1 for JAL, JALR and a branch whose condition holds (funct3, RiscvPkg
 * F3_B*). The target is pc + imm (JAL, branches) or rs1 + imm (JALR, bit 0 ignored as
 * the spec says). branch.misaligned=1 when bit 1 of the target is set: without the
 * C extension instructions are 4-byte aligned, a taken jump there must not complete.
 * link is pc + 4, the value JAL and JALR write to rd.
 *
 * Mig2Core instantiates it in EX, for the instruction in EX.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module Mig2Branch import Mig2Pkg::*, RiscvPkg::*; (
    // Only br, funct3 and imm are used.
    /* verilator lint_off UNUSEDSIGNAL */
    input  decoded_t dec,       // the instruction taken apart
    /* verilator lint_on UNUSEDSIGNAL */
    input  iaddr_t   pc,        // address of the instruction
    input  word_t    rs1_data,  // compared, and the base of JALR
    input  word_t    rs2_data,  // compared
    output branch_t  branch,    // taken, target, misaligned: to Mig2Control
    output word_t    link       // pc + 4 as a byte address: rd of JAL and JALR, next pc of
                                // the retire trace
);
    logic  eq;
    logic  lt;      // rs1 < rs2 signed
    logic  ltu;     // rs1 < rs2 unsigned
    logic  cond;    // branch condition holds
    // Byte address; bit 0 is ignored (JALR, as the spec says; 0 for the others).
    /* verilator lint_off UNUSEDSIGNAL */
    word_t target;
    /* verilator lint_on UNUSEDSIGNAL */

    assign eq  = rs1_data == rs2_data;
    assign lt  = $signed(rs1_data) < $signed(rs2_data);
    assign ltu = rs1_data < rs2_data;

    always_comb
        case (dec.funct3)
            F3_BEQ:  cond = eq;
            F3_BNE:  cond = !eq;
            F3_BLT:  cond = lt;
            F3_BGE:  cond = !lt;
            F3_BLTU: cond = ltu;
            F3_BGEU: cond = !ltu;
            default: cond = 1'b0;   // 010 and 011 are not branches
        endcase

    assign target = (dec.br.target_rs1 ? rs1_data : {pc, {IADDR_START{1'b0}}}) + dec.imm;

    assign branch.taken      = dec.br.jump || (dec.br.branch && cond);
    assign branch.target     = target[WIDTH-1:IADDR_START];
    assign branch.misaligned = target[1];

    assign link = {pc + 1'b1, {IADDR_START{1'b0}}};

endmodule

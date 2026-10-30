/* Mig2 ALU: value for rd of OP, OP-IMM, LUI and AUIPC, and the address rs1 + imm of loads
 * and stores, purely combinational.
 *
 * Operand a is rs1, or pc for AUIPC, or 0 for LUI; operand b is rs2 for OP, else the
 * immediate (dec.alu.a, dec.alu.b_imm). The library block Alu2 computes the operation with
 * the controls decode gave (dec.alu.alu2 = Alu2Pkg::ctrl_of of the operation): the RV32I
 * operations and the Zbb that reuse the ALU (ANDN, ORN, XNOR, MIN, MAX, ROL, ROR, RORI).
 * LUI is 0 + imm, AUIPC pc + imm, loads and stores rs1 + imm.
 *
 * Mig2Core instantiates it in EX, for the instruction in EX. result is rd's value
 * (rd_src RD_ALU) and the load/store address for Mig2Lsu and Mig2Control (mtval).
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module Mig2Alu import Mig2Pkg::*; (
    // Only alu and imm are used.
    /* verilator lint_off UNUSEDSIGNAL */
    input  decoded_t dec,       // the instruction taken apart
    /* verilator lint_on UNUSEDSIGNAL */
    input  iaddr_t   pc,        // address of the instruction, for AUIPC
    input  word_t    rs1_data,
    input  word_t    rs2_data,
    output word_t    result     // rd value, or the load/store address
);
    word_t a;           // operand a: rs1, pc or 0
    word_t b;           // operand b: rs2 or the immediate

    always_comb
        case (dec.alu.a)
            A_PC:    a = {pc, {IADDR_START{1'b0}}};
            A_ZERO:  a = '0;
            default: a = rs1_data;
        endcase
    assign b = dec.alu.b_imm ? dec.imm : rs2_data;

    Alu2 #(.WIDTH(WIDTH)) u_alu2(.ctrl(dec.alu.alu2), .a, .b, .out(result));

endmodule

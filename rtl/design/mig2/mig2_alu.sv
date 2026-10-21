/* Mig2 ALU: value for rd of OP, OP-IMM, LUI and AUIPC, purely combinational.
 *
 * Operand a is rs1, or pc for AUIPC, or 0 for LUI; operand b is rs2 for OP, else the
 * immediate. funct3 (RiscvPkg F3_*) selects the operation, alt (insn[30]) SUB and SRA.
 * One Alu1 adds, subtracts and does AND, OR, XOR; comparisons use its SUB: co=1 is
 * no borrow, a >= b unsigned. One BarrelShifter shifts by b[4:0].
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module Mig2Alu import Mig2Pkg::*, RiscvPkg::*, Alu1Pkg::*; (
    // Only alu, funct3, alt and imm are used.
    /* verilator lint_off UNUSEDSIGNAL */
    input  decoded_t                   dec,
    /* verilator lint_on UNUSEDSIGNAL */
    input  iaddr_t                     pc,        // address of the instruction, for AUIPC
    input  word_t                      rs1_data,
    input  word_t                      rs2_data,
    output word_t                      result
);
    word_t                a;
    word_t                b;
    logic [CMD_WIDTH-1:0] cmd;
    word_t                sum;      // Alu1 out
    logic                 co;       // Alu1 carry out
    word_t                shifted;
    logic                 lt_u;     // a < b unsigned
    logic                 lt_s;     // a < b signed
    logic                 a_sign;
    logic                 b_sign;

    // Operands.
    always_comb
        case (dec.alu.a)
            A_PC:    a = {pc, {IADDR_START{1'b0}}};
            A_ZERO:  a = '0;
            default: a = rs1_data;
        endcase
    assign b      = dec.alu.b_imm ? dec.imm : rs2_data;
    assign a_sign = a[WIDTH-1];
    assign b_sign = b[WIDTH-1];

    // Alu1 command by funct3; LUI and AUIPC add.
    always_comb
        if (!dec.alu.op)
            cmd = OP_ADD;
        else
            case (dec.funct3)
                F3_ADD_SUB:      cmd = dec.alu.sub ? OP_SUB : OP_ADD;
                F3_SLT, F3_SLTU: cmd = OP_SUB;   // compare by subtraction
                F3_XOR:          cmd = OP_XOR;
                F3_OR:           cmd = OP_OR;
                F3_AND:          cmd = OP_AND;
                default:         cmd = OP_ADD;   // shifts do not use Alu1
            endcase

    Alu1 #(.WIDTH(WIDTH)) u_alu1(.cmd(cmd), .in1(a), .in2(b), .co(co), .out(sum));

    // SLL left, SRL right with 0, SRA right with the sign bit.
    BarrelShifter #(.WIDTH(WIDTH)) u_barrel_shifter(
        .in(a), .shift_in_bit(dec.alt && a_sign), .shift(b[$clog2(WIDTH)-1:0]),
        .shift_rotate(1'b1), .left_right(dec.funct3 == F3_SLL), .out(shifted));

    // Comparisons from the subtraction a - b.
    assign lt_u = !co;
    assign lt_s = (a_sign != b_sign) ? a_sign : lt_u;

    // Result by funct3; LUI and AUIPC take the sum.
    always_comb
        if (!dec.alu.op)
            result = sum;
        else
            case (dec.funct3)
                F3_SLL, F3_SRL_SRA: result = shifted;
                F3_SLT:             result = {{(WIDTH-1){1'b0}}, lt_s};
                F3_SLTU:            result = {{(WIDTH-1){1'b0}}, lt_u};
                default:            result = sum;   // ADD, SUB, XOR, OR, AND
            endcase

endmodule

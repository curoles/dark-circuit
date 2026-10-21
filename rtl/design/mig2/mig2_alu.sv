/* Mig2 ALU: value for rd of OP, OP-IMM, LUI and AUIPC, purely combinational.
 *
 * Operand a is rs1, or pc for AUIPC, or 0 for LUI; operand b is rs2 for OP, else the
 * immediate. funct3 (RiscvPkg F3_*) selects the operation, alt (insn[30]) SUB and SRA.
 * One Alu1 adds, subtracts and does AND, OR, XOR; comparisons use its SUB: co=1 is
 * no borrow, a >= b unsigned. One BarrelShifter shifts by b[4:0].
 */
module Mig2Alu import Mig2Pkg::*, RiscvPkg::*, Alu1Pkg::*; (
    // Only kind, funct3, alt and imm are used.
    /* verilator lint_off UNUSEDSIGNAL */
    input  decoded_t                   dec,
    /* verilator lint_on UNUSEDSIGNAL */
    input  iaddr_t                     pc,        // address of the instruction, for AUIPC
    input  word_t                      rs1_data,
    input  word_t                      rs2_data,
    output word_t                      result
);
    // Fields of dec, selected with assign: Icarus warns about selects in always_comb.
    kind_t      kind;
    logic [2:0] funct3;
    logic       alt;
    word_t      imm;
    assign kind   = dec.kind;
    assign funct3 = dec.funct3;
    assign alt    = dec.alt;
    assign imm    = dec.imm;

    word_t                a;
    word_t                b;
    logic [CMD_WIDTH-1:0] cmd;
    word_t                sum;      // Alu1 out
    logic                 co;       // Alu1 carry out
    word_t                shifted;
    logic                 lt_u;     // a < b unsigned
    logic                 lt_s;     // a < b signed
    logic                 sub;      // OP with alt: SUB instead of ADD
    logic                 shift_left;
    logic                 a_sign;
    logic                 b_sign;

    // Operands.
    assign a      = (kind == KIND_AUIPC) ? {pc, {IADDR_START{1'b0}}} :
                    (kind == KIND_LUI)   ? '0 : rs1_data;
    assign b      = (kind == KIND_OP) ? rs2_data : imm;
    assign sub    = kind == KIND_OP && alt;
    assign a_sign = a[WIDTH-1];
    assign b_sign = b[WIDTH-1];

    // Alu1 command by funct3; LUI and AUIPC add.
    always_comb
        if (kind != KIND_OP && kind != KIND_OP_IMM)
            cmd = OP_ADD;
        else
            case (funct3)
                F3_ADD_SUB:      cmd = sub ? OP_SUB : OP_ADD;
                F3_SLT, F3_SLTU: cmd = OP_SUB;   // compare by subtraction
                F3_XOR:          cmd = OP_XOR;
                F3_OR:           cmd = OP_OR;
                F3_AND:          cmd = OP_AND;
                default:         cmd = OP_ADD;   // shifts do not use Alu1
            endcase

    Alu1 #(.WIDTH(WIDTH)) u_alu1(.cmd(cmd), .in1(a), .in2(b), .co(co), .out(sum));

    // SLL left, SRL right with 0, SRA right with the sign bit. shift_left is an assign:
    // Icarus does not find imported F3_SLL in a port expression (implicit wire).
    assign shift_left = funct3 == F3_SLL;

    BarrelShifter #(.WIDTH(WIDTH)) u_barrel_shifter(
        .in(a), .shift_in_bit(alt && a_sign), .shift(b[$clog2(WIDTH)-1:0]),
        .shift_rotate(1'b1), .left_right(shift_left), .out(shifted));

    // Comparisons from the subtraction a - b.
    assign lt_u = !co;
    assign lt_s = (a_sign != b_sign) ? a_sign : lt_u;

    // Result by funct3; LUI and AUIPC take the sum.
    always_comb
        if (kind != KIND_OP && kind != KIND_OP_IMM)
            result = sum;
        else
            case (funct3)
                F3_SLL, F3_SRL_SRA: result = shifted;
                F3_SLT:             result = {{(WIDTH-1){1'b0}}, lt_s};
                F3_SLTU:            result = {{(WIDTH-1){1'b0}}, lt_u};
                default:            result = sum;   // ADD, SUB, XOR, OR, AND
            endcase

endmodule

/* Operations and controls of Alu2.
 *
 * A user names the operation (op_e) and gives Alu2 its controls, ctrl_of(op): a CPU calls
 * ctrl_of in decode and carries ctrl_t down the pipeline, so that Alu2 decodes nothing.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
package Alu2Pkg;

    // Operations: out = a op b. Shifts and rotates move a by b mod WIDTH positions.
    typedef enum logic [4:0] {
        ALU2_ADD,
        ALU2_SUB,
        ALU2_AND,
        ALU2_OR,
        ALU2_XOR,
        ALU2_ANDN,      // a & ~b
        ALU2_ORN,       // a | ~b
        ALU2_XNOR,      // ~(a ^ b)
        ALU2_SLT,       // a < b signed: 1, else 0
        ALU2_SLTU,      // a < b unsigned
        ALU2_MIN,       // the smaller, signed
        ALU2_MINU,      // the smaller, unsigned
        ALU2_MAX,       // the larger, signed
        ALU2_MAXU,      // the larger, unsigned
        ALU2_SLL,       // shift left, zeros in
        ALU2_SRL,       // shift right, zeros in
        ALU2_SRA,       // shift right, copies of the sign bit in
        ALU2_ROL,       // rotate left
        ALU2_ROR        // rotate right
    } op_e;

    // What out is.
    typedef enum logic [1:0] {
        RES_ALU1,       // Alu1's out: a sum, a difference, a logic operation
        RES_SHIFT,      // the BarrelShifter's out
        RES_LT,         // the compare a < b, 0 or 1
        RES_MINMAX      // a or b, picked by the compare
    } res_e;

    // Controls of Alu2, from ctrl_of.
    typedef struct packed {
        Alu1Pkg::op_e cmd;          // Alu1: ADD, SUB (also for the compare), AND, OR, XOR
        logic         b_inv;        // Alu1 gets ~b: ANDN, ORN, XNOR
        logic         cmp_unsigned; // the compare is unsigned: SLTU, MINU, MAXU
        logic         pick_max;     // MIN, MAX: the larger
        logic         shift_left;   // SLL, ROL
        logic         shift_arith;  // SRA: copies of the sign bit in
        logic         rotate;       // ROL, ROR
        res_e         res;
    } ctrl_t;

    // The controls of an operation. Field by field: Icarus does not parse named assignment
    // patterns.
    function automatic ctrl_t ctrl_of(op_e op);
        ctrl_t c;
        c.cmd          = Alu1Pkg::OP_ADD;
        c.b_inv        = 1'b0;
        c.cmp_unsigned = 1'b0;
        c.pick_max     = 1'b0;
        c.shift_left   = 1'b0;
        c.shift_arith  = 1'b0;
        c.rotate       = 1'b0;
        c.res          = RES_ALU1;
        case (op)
            ALU2_SUB:  c.cmd = Alu1Pkg::OP_SUB;
            ALU2_AND:  c.cmd = Alu1Pkg::OP_AND;
            ALU2_OR:   c.cmd = Alu1Pkg::OP_OR;
            ALU2_XOR:  c.cmd = Alu1Pkg::OP_XOR;
            ALU2_ANDN: begin c.cmd = Alu1Pkg::OP_AND; c.b_inv = 1'b1; end
            ALU2_ORN:  begin c.cmd = Alu1Pkg::OP_OR;  c.b_inv = 1'b1; end
            ALU2_XNOR: begin c.cmd = Alu1Pkg::OP_XOR; c.b_inv = 1'b1; end
            ALU2_SLT:  begin c.cmd = Alu1Pkg::OP_SUB; c.res = RES_LT; end
            ALU2_SLTU: begin c.cmd = Alu1Pkg::OP_SUB; c.res = RES_LT; c.cmp_unsigned = 1'b1; end
            ALU2_MIN:  begin c.cmd = Alu1Pkg::OP_SUB; c.res = RES_MINMAX; end
            ALU2_MINU: begin
                c.cmd = Alu1Pkg::OP_SUB; c.res = RES_MINMAX; c.cmp_unsigned = 1'b1;
            end
            ALU2_MAX:  begin c.cmd = Alu1Pkg::OP_SUB; c.res = RES_MINMAX; c.pick_max = 1'b1; end
            ALU2_MAXU: begin
                c.cmd = Alu1Pkg::OP_SUB; c.res = RES_MINMAX; c.pick_max = 1'b1;
                c.cmp_unsigned = 1'b1;
            end
            ALU2_SLL:  begin c.res = RES_SHIFT; c.shift_left = 1'b1; end
            ALU2_SRL:  c.res = RES_SHIFT;
            ALU2_SRA:  begin c.res = RES_SHIFT; c.shift_arith = 1'b1; end
            ALU2_ROL:  begin c.res = RES_SHIFT; c.shift_left = 1'b1; c.rotate = 1'b1; end
            ALU2_ROR:  begin c.res = RES_SHIFT; c.rotate = 1'b1; end
            default:   ;    // ALU2_ADD; the codes after ALU2_ROR are no operation
        endcase
        return c;
    endfunction

endpackage

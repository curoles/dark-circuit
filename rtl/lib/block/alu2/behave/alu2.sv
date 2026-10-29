/* Alu2: the integer operations of a CPU's ALU, behavioral, combinational: out = a op b with
 * the controls ctrl = Alu2Pkg::ctrl_of(op).
 *
 * Operations (Alu2Pkg::op_e): ADD, SUB, AND, OR, XOR; ANDN, ORN, XNOR (b inverted); SLT,
 * SLTU (a < b: 1 or 0); MIN, MINU, MAX, MAXU; SLL, SRL, SRA; ROL, ROR. Nothing here knows
 * an instruction set: a CPU maps its instructions to operations. The semantics are those
 * RISC-V needs (RV32I/RV64I and Zbb): shifts and rotates move by b mod WIDTH (the low
 * log2(WIDTH) bits of b), SLT and SLTU give 0 or 1 zero-extended.
 *
 * Built of library blocks: Alu1 adds, subtracts and does AND, OR, XOR, with b inverted for
 * ANDN, ORN, XNOR (only Alu1's b: the compare and the shifter use b as it is). The compare
 * uses Alu1's SUB: carry out 1 is no borrow, a >= b unsigned; signed: the sign of a when
 * the signs differ. MIN, MAX pick a or b by it. A BarrelShifter shifts and rotates a.
 * WIDTH is a power of 2, 2 or more.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
`include "dark_circuit_assert.svh"

module Alu2 import Alu2Pkg::*; #(
    parameter  WIDTH       = 32,
    localparam SHIFT_WIDTH = $clog2(WIDTH)
)(
    input  ctrl_t            ctrl,  // ctrl_of(the operation)
    input  wire [WIDTH-1:0]  a,
    input  wire [WIDTH-1:0]  b,
    output logic [WIDTH-1:0] out
);
    `DC_STATIC_ASSERT(a_width_power_of_2, WIDTH >= 2 && (WIDTH & (WIDTH - 1)) == 0)

    logic [WIDTH-1:0] b_alu1;   // b into Alu1: inverted for ANDN, ORN, XNOR
    logic [WIDTH-1:0] sum;      // Alu1's out
    logic             co;       // Alu1's carry out
    logic [WIDTH-1:0] shifted;  // the BarrelShifter's out
    logic             lt_u;     // a < b unsigned (from SUB)
    logic             lt_s;     // a < b signed
    logic             lt;       // the compare of the operation
    logic             pick_a;   // MIN, MAX: a, else b

    // @kb: rtl/lib/block/alu2/design
    assign b_alu1 = ctrl.b_inv ? ~b : b;

    Alu1 #(.WIDTH(WIDTH)) u_alu1(.cmd(ctrl.cmd), .in1(a), .in2(b_alu1), .co, .out(sum));

    BarrelShifter #(.WIDTH(WIDTH)) u_barrel_shifter(
        .in(a), .shift_in_bit(ctrl.shift_arith && a[WIDTH-1]), .shift(b[SHIFT_WIDTH-1:0]),
        .shift_rotate(!ctrl.rotate), .left_right(ctrl.shift_left), .out(shifted));

    assign lt_u   = !co;
    assign lt_s   = (a[WIDTH-1] != b[WIDTH-1]) ? a[WIDTH-1] : lt_u;
    assign lt     = ctrl.cmp_unsigned ? lt_u : lt_s;
    assign pick_a = lt ^ ctrl.pick_max;

    always_comb
        case (ctrl.res)
            RES_ALU1:   out = sum;
            RES_SHIFT:  out = shifted;
            RES_LT:     out = {{(WIDTH-1){1'b0}}, lt};
            RES_MINMAX: out = pick_a ? a : b;
        endcase

endmodule

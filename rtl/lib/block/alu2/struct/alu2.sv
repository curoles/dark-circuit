/* Alu2: the integer operations of a CPU's ALU, made of blocks and gates, combinational:
 * out = a op b with the controls ctrl = Alu2Pkg::ctrl_of(op).
 *
 * Same ports, parameters and result as the behave version (see there for the operations and
 * their semantics). Gates: b is inverted by an Xor2 with b_inv; Alu1 and the BarrelShifter
 * are the library blocks; the compare takes Alu1's carry out of SUB (unsigned) or, when the
 * signs differ, the sign of a (signed); MIN, MAX pick a or b with a Mux2; a Mux4 selects
 * out by ctrl.res.
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
    output wire [WIDTH-1:0]  out
);
    `DC_STATIC_ASSERT(a_width_power_of_2, WIDTH >= 2 && (WIDTH & (WIDTH - 1)) == 0)

    wire [WIDTH-1:0] b_alu1;        // b into Alu1: inverted for ANDN, ORN, XNOR
    wire [WIDTH-1:0] sum;           // Alu1's out
    wire             co;            // Alu1's carry out
    wire [WIDTH-1:0] shifted;       // the BarrelShifter's out
    wire             shift_in_bit;  // SRA: the sign bit of a
    wire             shift_rotate;  // 1 shift, 0 rotate
    wire             lt_u;          // a < b unsigned (from SUB)
    wire             lt_s;          // a < b signed
    wire             signs_differ;
    wire             lt;            // the compare of the operation
    wire             pick_a;        // MIN, MAX: a, else b
    wire [WIDTH-1:0] result [4];    // result[r]: out for ctrl.res == r

    // @kb: rtl/lib/block/alu2/design
    Xor2 #(WIDTH) u_xor2_b_inv(.in1(b), .in2({WIDTH{ctrl.b_inv}}), .out(b_alu1));

    Alu1 #(.WIDTH(WIDTH)) u_alu1(.cmd(ctrl.cmd), .in1(a), .in2(b_alu1), .co, .out(sum));

    And2 #(1) u_and2_shift_in(.in1(ctrl.shift_arith), .in2(a[WIDTH-1]), .out(shift_in_bit));
    Inv  #(1) u_inv_rotate   (.in(ctrl.rotate), .out(shift_rotate));
    BarrelShifter #(.WIDTH(WIDTH)) u_barrel_shifter(
        .in(a), .shift_in_bit, .shift(b[SHIFT_WIDTH-1:0]), .shift_rotate,
        .left_right(ctrl.shift_left), .out(shifted));

    // The compare from the subtraction a - b.
    Inv  #(1) u_inv_co       (.in(co), .out(lt_u));
    Xor2 #(1) u_xor2_signs   (.in1(a[WIDTH-1]), .in2(b[WIDTH-1]), .out(signs_differ));
    Mux2 #(1) u_mux2_lt_s    (.in0(lt_u), .in1(a[WIDTH-1]), .sel(signs_differ), .out(lt_s));
    Mux2 #(1) u_mux2_lt      (.in0(lt_s), .in1(lt_u), .sel(ctrl.cmp_unsigned), .out(lt));
    Xor2 #(1) u_xor2_pick    (.in1(lt), .in2(ctrl.pick_max), .out(pick_a));

    assign result[RES_ALU1]  = sum;
    assign result[RES_SHIFT] = shifted;
    assign result[RES_LT]    = {{(WIDTH-1){1'b0}}, lt};
    Mux2 #(WIDTH) u_mux2_minmax(.in0(b), .in1(a), .sel(pick_a), .out(result[RES_MINMAX]));

    Mux4 #(WIDTH) u_mux4_out(.in0(result[0]), .in1(result[1]), .in2(result[2]),
                             .in3(result[3]), .sel(ctrl.res), .out(out));

endmodule

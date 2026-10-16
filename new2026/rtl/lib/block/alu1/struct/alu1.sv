/* ALU with arithmetic and logic commands of Alu1Pkg, made of parts and gates.
 *
 * Author: Igor Lesik 2020
 *
 * cmd is Alu1Pkg::Op, out is the result, combinational.
 * co is carry out of arithmetic commands, 0 for logic commands.
 * Subtraction uses 2's complement: -in2 = ~in2 + 1, so in1 - in2 = in1 + ~in2 + 1,
 * and co of subtraction is 1 when there is no borrow (in1 >= in2).
 *
 * Commands are encoded so that no decoding is needed:
 *   S1 S0 C = cmd[2:0]  arithmetic: adder in2 is 0, in2, ~in2 or all ones by S1 S0,
 *                       carry in is C; cmd 0..7 are all 8 combinations
 *   cmd[1:0]            logic: AND, OR, XOR, NOT
 *   cmd[3]              1 selects logic
 *
 * References:
 * - https://www.egr.msu.edu/classes/ece410/mason/files/Ch12.pdf
 */
module Alu1 #(
    parameter  WIDTH     = 64,
    localparam CMD_WIDTH = Alu1Pkg::CMD_WIDTH
)(
    input  wire [CMD_WIDTH-1:0] cmd,  // Alu1Pkg::Op
    input  wire [WIDTH-1:0]     in1,
    input  wire [WIDTH-1:0]     in2,
    output wire                 co,   // carry out of arithmetic; for SUB 1 means no borrow; 0 for logic
    output wire [WIDTH-1:0]     out
);
    wire [WIDTH-1:0] in2_inv, adder_in2, adder_out;
    wire [WIDTH-1:0] and_out, or_out, xor_out, not_out, logic_out;
    wire             adder_co, arith;

    // Arithmetic: adder in2 by S1 S0 = cmd[2:1]: 0, in2, ~in2, all ones; carry in cmd[0].
    Inv  #(WIDTH) u_inv_in2(.in(in2), .out(in2_inv));
    Mux4 #(WIDTH) u_mux4_adder_in2(.in0({WIDTH{1'b0}}), .in1(in2), .in2(in2_inv), .in3({WIDTH{1'b1}}),
                                   .sel(cmd[2:1]), .out(adder_in2));
    RippleCarryAdder #(.WIDTH(WIDTH)) u_ripple_carry_adder(
        .in1(in1), .in2(adder_in2), .ci(cmd[0]), .co(adder_co), .sum(adder_out));

    // Logic by cmd[1:0]: AND, OR, XOR, NOT.
    And2 #(WIDTH) u_and2   (.in1(in1), .in2(in2), .out(and_out));
    Or2  #(WIDTH) u_or2    (.in1(in1), .in2(in2), .out(or_out));
    Xor2 #(WIDTH) u_xor2   (.in1(in1), .in2(in2), .out(xor_out));
    Inv  #(WIDTH) u_inv_in1(.in(in1), .out(not_out));
    Mux4 #(WIDTH) u_mux4_logic(.in0(and_out), .in1(or_out), .in2(xor_out), .in3(not_out),
                               .sel(cmd[1:0]), .out(logic_out));

    // cmd[3] selects logic; co is 0 for logic.
    Mux2 #(WIDTH) u_mux2_out (.in0(adder_out), .in1(logic_out), .sel(cmd[3]), .out(out));
    Inv  #(1)     u_inv_arith(.in(cmd[3]), .out(arith));
    And2 #(1)     u_and2_co  (.in1(adder_co), .in2(arith), .out(co));

endmodule

/* ALU with arithmetic and logic commands of Alu1Pkg, behavioral.
 *
 * Author: Igor Lesik 2020
 *
 * cmd is Alu1Pkg::Op, out is the result, combinational.
 * co is carry out of arithmetic commands, 0 for logic commands.
 * Subtraction uses 2's complement: -in2 = ~in2 + 1, so in1 - in2 = in1 + ~in2 + 1,
 * and co of subtraction is 1 when there is no borrow (in1 >= in2).
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
    output reg                  co,   // carry out of arithmetic; for SUB 1 means no borrow; 0 for logic
    output reg  [WIDTH-1:0]     out
);
    import Alu1Pkg::*;

    localparam [WIDTH-1:0] ONES = {WIDTH{1'b1}};

    // Operands are extended with 0 before ~ and +, so carry out lands in co.
    always_comb
        case (cmd)
            OP_TRANSFER:   {co, out} = {1'b0, in1};
            OP_INC:        {co, out} = {1'b0, in1} + 1'b1;
            OP_ADD:        {co, out} = {1'b0, in1} + {1'b0, in2};
            OP_ADD_PLUS1:  {co, out} = {1'b0, in1} + {1'b0, in2} + 1'b1;
            OP_SUB_MINUS1: {co, out} = {1'b0, in1} + {1'b0, ~in2};
            OP_SUB:        {co, out} = {1'b0, in1} + {1'b0, ~in2} + 1'b1;
            OP_DEC:        {co, out} = {1'b0, in1} + {1'b0, ONES};
            OP_TRANSFER2:  {co, out} = {1'b0, in1} + {1'b0, ONES} + 1'b1;
            OP_AND, 4'd12: {co, out} = {1'b0, in1 & in2};
            OP_OR,  4'd13: {co, out} = {1'b0, in1 | in2};
            OP_XOR, 4'd14: {co, out} = {1'b0, in1 ^ in2};
            OP_NOT, 4'd15: {co, out} = {1'b0, ~in1};
        endcase

endmodule

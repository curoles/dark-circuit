localparam ALU1_CMD_WIDTH=2;
localparam ALU1_NR_COMMANDS=2;

/*
 *
 *
 * Substraction is using 2's complements.
 * Negating B is to find its 2's complement, 2's complement of B is ~B + 1,
 * that is invert and add 1.
 * Therefore A - B = A + B2s = A + ~B + 1.
 * When using RippleCarryAdder we need:
 * 1. set carry in `ci` to HI for +1, ci = sub_add;
 * 2. B' = ~B = B XOR sub_add.
 *
 *
 *
 *
 *
 *
 *
 *
 *
 */
module Alu1 #(
    parameter WIDTH,
    localparam CMD_WIDTH = ALU1_CMD_WIDTH
)(
    input  wire [CMD_WIDTH-1:0] cmd,
    input  wire [WIDTH-1:0]     in1,
    input  wire [WIDTH-1:0]     in2,
    output wire                 co,
    output wire [WIDTH-1:0]     out
);

    localparam CMD_ADD = 0;
    localparam CMD_SUB = 1;


    wire [WIDTH-1:0] in2_inv;

    INV#(WIDTH) inv2_(.in(in2), .out(in2_inv));

    wire [WIDTH-1:0] adder_in1;
    wire [WIDTH-1:0] adder_in2;
    wire [WIDTH-1:0] adder_out;
    wire             adder_ci;

    assign adder_in1 = in1;

    assign adder_ci = (cmd == CMD_SUB)? 1 : 0;

    assign adder_in2 = (cmd == CMD_SUB)? in2_inv : in2;

    RippleCarryAdder#(WIDTH) adder(adder_in1, adder_in1, adder_ci, co, adder_out);




endmodule: Alu1

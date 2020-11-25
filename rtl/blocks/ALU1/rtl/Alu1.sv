localparam ALU1_CMD_WIDTH=3;
localparam ALU1_NR_COMMANDS=8;

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
 * <script type="WaveDrom">
 * { assign:[
 *   ["adder_input2",
 *     ["|", ["&", "in", "S0"],
 *           ["&", ["~","in"], "S1"]
 *     ]
 *   ]
 * ]}
 * </script>
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

                                   //S012 C cmd
    localparam CMD_TRANSFER   = 0; // 000 0 000 out = in1
    localparam CMD_INC        = 1; // 000 1 001 out = in1 + 1
    localparam CMD_ADD        = 2; // 100 0 010 out = in1 + in2
    localparam CMD_ADD_PLUS1  = 3; // 100 1 011 out = in1 + in2 + 1
    localparam CMD_SUB_MINUS1 = 4; // 010 0 100 out = in1 + ~in2
    localparam CMD_SUB        = 5; // 010 1 101 out = in1 + ~in2 + 1
    localparam CMD_DEC        = 6; // 110 0 110 out = in1 - 1 (in1 + 111=in1 + 000 - 1=in1 - 1)
    localparam CMD_TRANSFER2  = 7; // 110 1 111 out = in1

    wire [2:0] opsel;

    assign opsel[0] = (cmd == CMD_ADD || cmd == CMD_ADD_PLUS1 ||
        cmd == CMD_DEC || cmd == CMD_TRANSFER2);

    assign opsel[1] = cmd[2];

    wire [WIDTH-1:0] in2_inv;

    INV#(WIDTH) inv2_(.in(in2), .out(in2_inv));

    wire [WIDTH-1:0] adder_in1;
    wire [WIDTH-1:0] adder_in2;
    wire [WIDTH-1:0] adder_out;
    wire             adder_ci;

    assign adder_in1 = in1;

    assign adder_ci = cmd[0];

    generate; genvar i;
    for (i = 0; i < WIDTH; i++) begin : in2_sel
        assign adder_in2[i] = (in2[i] & opsel[0]) | (in2_inv[i] & opsel[1]);
    end
    endgenerate

    RippleCarryAdder#(WIDTH) adder_(
        .in1(adder_in1),
        .in2(adder_in2),
        .ci(adder_ci),
        .co(co),
        .sum(adder_out)
    );

    assign out = adder_out;


endmodule: Alu1

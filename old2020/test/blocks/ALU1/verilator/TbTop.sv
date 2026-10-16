/* Verilog TB top module.
 *
 * Copyright Igor Lesik 2020.
 *
 * External C-TB drives the inputs and checks the outputs.
 */
module TbTop #(
    localparam WIDTH = 64,
    localparam CMD_WIDTH = ALU1_CMD_WIDTH
)(
    input  wire                 clk,
    input  wire [CMD_WIDTH-1:0] cmd,
    input  wire [WIDTH-1:0]     in1,
    input  wire [WIDTH-1:0]     in2,
    output wire [WIDTH-1:0]     out
);

    localparam NR_COMMANDS /* verilator public */ = ALU1_NR_COMMANDS;

    Alu1#(.WIDTH(WIDTH))
        alu_(.cmd(cmd), .in1(in1), .in2(in2), .out(out));


endmodule: TbTop

/* Verilog TB top module.
 *
 * Copyright Igor Lesik 2020.
 *
 * External C-TB drives the inputs and checks the outputs.
 */
module TbTop #(
    localparam WIDTH = 64
)(
    input  wire             clk,
    input  wire [WIDTH-1:0] in1,
    input  wire [WIDTH-1:0] in2,
    input  wire             ci,
    output reg  [WIDTH-1:0] sum,
    output reg              co
);

    RippleCarryAdder#(.WIDTH(WIDTH))
        adder_(.in1(in1),
               .in2(in2),
               .ci(ci),
               .co(co),
               .sum(sum)
    );

endmodule: TbTop

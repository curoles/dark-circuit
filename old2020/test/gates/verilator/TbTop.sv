/* Verilog TB top module.
 *
 * Copyright Igor Lesik 2020.
 *
 * External C-TB drives the inputs and checks the outputs.
 */
module TbTop(
    input  wire          clk,
    input  wire [64-1:0] in1,
    input  wire [64-1:0] in2,
    input  wire [64-1:0] in3,
    output wire [64-1:0] out_inv,
    output wire [64-1:0] out_nand2,
    output wire [64-1:0] out_mux2
);

    INV#(64) inv_(.in(in1), .out(out_inv));

    NAND2#(64) nand2_(.in1(in1), .in2(in2), .out(out_nand2));

    MUX2#(64) mux2_(.in1(in1), .in2(in2), .sel(in3[0]), .out(out_mux2));

endmodule: TbTop

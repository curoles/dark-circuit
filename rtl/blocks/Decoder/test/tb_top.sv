/* Decoder TB.
 * Author: Igor Lesik 2020
 *
 *
 *
 *
 */



/* Verilog TB top module.
 *
 * External C-TB drives the inputs and checks the outputs.
 */
module tb_top(
    input  wire          clk,
    input  wire [3-1:0]  n,
    output wire [8-1:0]  dec,
    output wire [3-1:0]  enc
);

Decoder#(.SIZE(3)) decoder_(.in(n), .en(1), .out(dec));

Encoder8_3 encoder_(.in(dec), .out(enc));

endmodule: tb_top

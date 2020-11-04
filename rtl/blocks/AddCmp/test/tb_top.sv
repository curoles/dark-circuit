/* Adder-Comparator TB.
 * Author: Igor Lesik 2019
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
    input  wire [50-1:0] a,
    input  wire [50-1:0] b,
    input  wire [50-1:0] c,
    output wire          eq
);

AddCmp50 u_addcmp(
  .a(a),
  .b(b),
  .c(c),
  .eq(eq)
);

endmodule: tb_top

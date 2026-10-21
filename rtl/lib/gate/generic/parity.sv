/* Return 1 if input vector has odd number of 1's.
 *
 * Verilog Reduction Operators
 * - and(&), nand(~&), or(|), nor(~|) xor(^), xnor(^~,~^)
 * - operate on only one operand
 * - perform a bitwise operation on all bits of the operand
 * - return a 1-bit result
 * - work from right to left, bit by bit
 *
 * @author    Igor Lesik
 * @copyright 2014 Igor Lesik, MIT License
 */

/* Return 1 if input vector has odd number of 1's.
 *
 */
module Parity #(
    parameter WIDTH = 1
)(
   input  wire [WIDTH-1:0] in,
   output wire             parity
);

assign parity = ^in;

endmodule

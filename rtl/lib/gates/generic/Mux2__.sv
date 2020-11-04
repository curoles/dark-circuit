/**@file
 * @brief     Multiplexer 
 * @author    Igor Lesik
 * @copyright Igor Lesik 2020
 *
 *  
 *                  +------+
 *                  |      |
 *  in1 +-----------+ NAND |
 *                  |      |o+-+    +------+
 *  sel +-----+-----+      |   |    |      |
 *            |     |      |   |    |      |
 *            |     +------+   +----+ NAND |
 *            |                     |      |o+----+ out
 *            |     +------+   +----+      |
 *            |     |      |   |    |      |
 *            +---+o| NAND |   |    |      |
 *                  |      |o+-+    +------+
 *  in2 +-----------+      |
 *                  |      |
 *                  +------+
 *  
 */

module Mux2 #(
    parameter WIDTH = 1
)(
    input  wire [WIDTH-1:0]  in1,
    input  wire [WIDTH-1:0]  in2,
    input  wire              sel,
    output wire [WIDTH-1:0]  out
);

//TODO

endmodule

/** Complex gate OR-AND-Invertor
 *
 *
 *
 *  in1 ----------+--\
 *                )OR +----+
 *  in2 ----------+--/|    |
 *                    |NAND|o-----
 *  in3 ----------+--\|    |
 *                )OR +----+
 *  in4 ----------+--/
 *
 */

module OAI22 #(
    parameter WIDTH = 8
)(
    input  wire [WIDTH-1:0] in1,
    input  wire [WIDTH-1:0] in2,
    input  wire [WIDTH-1:0] in3,
    input  wire [WIDTH-1:0] in4,
    output wire [WIDTH-1:0] out
);

assign out = ~((in1 | in2) & (in3 | in4));

endmodule

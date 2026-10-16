/**
 *
 *
 *
 *  in1 ----------+--\
 *                )OR +----+
 *        +-------+--/|    |
 *        |           |NAND|o-----
 *  in2 ----------+--\|    |
 *        |       )OR +----+
 * sel  --+-NOT---+--/
 *
 */

module Mux2I #(
    parameter WIDTH = 8
)(
    input  wire [WIDTH-1:0] in1,
    input  wire [WIDTH-1:0] in2,
    input  wire             sel,
    output wire [WIDTH-1:0] out
);

wire [WIDTH-1:0] sels;
wire [WIDTH-1:0] nsels;
assign sels = {WIDTH{sel}};
assign nsels = {WIDTH{~sel}};

OAI22 oai22_(.in1(in1), .in2(sels), .in3(in2), in4(nsels));

endmodule

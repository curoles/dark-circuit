/* Inverting 2:1 Multiplexer made with OAI22, out = ~(sel ? in2 : in1).
 *
 * <pre>
 *  in1 ----------+--\
 *                )OR +----+
 *        +-------+--/|    |
 *        |           |NAND|o----- out
 *  in2 ----------+--\|    |
 *        |       )OR +----+
 * sel  --+-NOT---+--/
 * </pre>
 */
module Mux2i #(
    parameter WIDTH = 1
)(
    input  wire [WIDTH-1:0] in1,  // inverted to out when sel is 0
    input  wire [WIDTH-1:0] in2,  // inverted to out when sel is 1
    input  wire             sel,
    output wire [WIDTH-1:0] out
);

    wire [WIDTH-1:0] sels;
    wire [WIDTH-1:0] nsels;
    assign sels = {WIDTH{sel}};
    assign nsels = {WIDTH{~sel}};

    Oai22 #(WIDTH) u_oai22(.in1(in1), .in2(sels), .in3(in2), .in4(nsels), .out(out));

endmodule

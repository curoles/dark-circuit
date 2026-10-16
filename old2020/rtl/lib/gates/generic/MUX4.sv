/* 4:1 Multiplexer
 *
 */
module MUX4 #(
    parameter WIDTH = 1
)(
    input  wire [WIDTH-1:0]  in1,
    input  wire [WIDTH-1:0]  in2,
    input  wire [WIDTH-1:0]  in3,
    input  wire [WIDTH-1:0]  in4,
    input  wire [1:0]        sel,
    output wire [WIDTH-1:0]  out
);

    Mux4#(WIDTH) mux4_(.in1, .in2, .in3, .in4, .sel, .out);

endmodule

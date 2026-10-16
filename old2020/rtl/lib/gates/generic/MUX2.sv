/* 2:1 Multiplexer
 *
 */
module MUX2 #(
    parameter WIDTH = 1
)(
    input  wire [WIDTH-1:0]  in1,
    input  wire [WIDTH-1:0]  in2,
    input  wire              sel,
    output wire [WIDTH-1:0]  out
);

    Mux2#(WIDTH) mux2_(.in1(in1), .in2(in2), .sel(sel), .out(out));

endmodule

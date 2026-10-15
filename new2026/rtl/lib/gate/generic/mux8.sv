/* 8 inputs Multiplexer
 * Author:    Igor Lesik 2014
 * Copyright: Igor Lesik 2014
 *
 */
module Mux8 #(
    parameter WIDTH = 1
)(
    input  wire [WIDTH-1:0]  in1,
    input  wire [WIDTH-1:0]  in2,
    input  wire [WIDTH-1:0]  in3,
    input  wire [WIDTH-1:0]  in4,
    input  wire [WIDTH-1:0]  in5,
    input  wire [WIDTH-1:0]  in6,
    input  wire [WIDTH-1:0]  in7,
    input  wire [WIDTH-1:0]  in8,
    input  wire [2:0]        sel,
    output wire [WIDTH-1:0]  out
);
    wire [WIDTH-1:0] out14, out58;

    Mux2#(.WIDTH(WIDTH)) u_mux2(.in1(out14), .in2(out58), .sel(sel[2]), .out(out));

    Mux4#(.WIDTH(WIDTH)) u_mux4_1(.in1(in1), .in2(in2), .in3(in3), .in4(in4), .sel(sel[1:0]), .out(out14));
    Mux4#(.WIDTH(WIDTH)) u_mux4_2(.in1(in5), .in2(in6), .in3(in7), .in4(in8), .sel(sel[1:0]), .out(out58));

endmodule

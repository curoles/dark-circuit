/* 8 inputs Multiplexer, sel k selects input in<k>.
 *
 * Made of Mux4 and Mux2 gates.
 *
 * @author    Igor Lesik
 * @copyright 2014 Igor Lesik, MIT License
 */
module Mux8 #(
    parameter WIDTH = 1
)(
    input  wire [WIDTH-1:0]  in0,
    input  wire [WIDTH-1:0]  in1,
    input  wire [WIDTH-1:0]  in2,
    input  wire [WIDTH-1:0]  in3,
    input  wire [WIDTH-1:0]  in4,
    input  wire [WIDTH-1:0]  in5,
    input  wire [WIDTH-1:0]  in6,
    input  wire [WIDTH-1:0]  in7,
    input  wire [2:0]        sel,
    output wire [WIDTH-1:0]  out
);
    wire [WIDTH-1:0] out03, out47;

    Mux2#(.WIDTH(WIDTH)) u_mux2(.in0(out03), .in1(out47), .sel(sel[2]), .out(out));

    Mux4#(.WIDTH(WIDTH)) u_mux4_0(.in0(in0), .in1(in1), .in2(in2), .in3(in3), .sel(sel[1:0]), .out(out03));
    Mux4#(.WIDTH(WIDTH)) u_mux4_1(.in0(in4), .in1(in5), .in2(in6), .in3(in7), .sel(sel[1:0]), .out(out47));

endmodule

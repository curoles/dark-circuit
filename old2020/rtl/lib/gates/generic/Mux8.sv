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

    Mux2#(.WIDTH(WIDTH)) _m2(out14, out58, sel[2], out);

    Mux4#(.WIDTH(WIDTH)) _m41(in1, in2, in3, in4, sel[1:0], out14);
    Mux4#(.WIDTH(WIDTH)) _m42(in5, in6, in7, in8, sel[1:0], out58);

endmodule

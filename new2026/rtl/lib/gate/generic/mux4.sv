/* 4:1 Multiplexer, sel k selects input in<k>.
 * Author: Igor Lesik 2014
 *
 */

module Mux4 #(
    parameter WIDTH = 1
)(
    input  wire [WIDTH-1:0]  in0,
    input  wire [WIDTH-1:0]  in1,
    input  wire [WIDTH-1:0]  in2,
    input  wire [WIDTH-1:0]  in3,
    input  wire [1:0]        sel,
    output wire [WIDTH-1:0]  out
);

assign out = (sel == 0) ? in0 :
             (sel == 1) ? in1 :
             (sel == 2) ? in2 : in3;
/*
 assign Z =    (~S1 & ~S0 & I0)
              | (~S1 &  S0 & I1)
              | ( S1 & ~S0 & I2)
              | ( S1 &  S0 & I3);*/
endmodule

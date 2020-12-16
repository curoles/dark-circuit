`include "clog2.svh"

/* Barrel Shifter
 * Author: Igor Lesik 2019-2020
 * Copyright: Igor Lesik 2019-2020
 *
 */
module BarrelShifter #(
    parameter WIDTH = 64,
    parameter SHIFT_WIDTH = `CLOG2(WIDTH) // number of shift/rotate bits
)(
    input  wire [WIDTH-1:0]       in,
    input  wire [SHIFT_WIDTH-1:0] shift,        // number of shifts
    input  wire                   shift_rotate, // shift or rotate
    input  wire                   left_right,   // shift/rotate left or right
    output wire [WIDTH-1:0]       out
);

    wire [WIDTH-1:0] ain; // "in" or reversed "in"

    wire [WIDTH-1:0] res; // result of shifting

    genvar i;

    // We implement internal logic that shift/rotate LEFT.
    // The direction of the final shift/rotate operation is implemented by reversing
    // the input and output vector.
    generate //: reverse_vectors
        for (i = 0; i < WIDTH; i = i + 1)
        begin: gen_reverse
            MUX2#(.WIDTH(1)) mux_reverse_in_ (.in1(in[i]), .in2(in[WIDTH-1-i]), .sel(left_right), .out(ain[i]));
            MUX2#(.WIDTH(1)) mux_reverse_out_ (.in1(res[i]), .in2(res[WIDTH-1-i]), .sel(left_right), .out(out[i]));
        end: gen_reverse
    endgenerate

    // The shift/rotate (left) operation is done in stages where each stage performs
    // a shift/rotate operation of a different size.
    // For example, a 5 bits shift operation would result in a shift of 4 and a shift of 1
    // where the stage that performs the shift of 2 would not do any shift.
    // The select vector binary encoding is actually to enable the different stages of the barrel shifter.

    // {stage[i+1][WIDTH-(2**i)-1:0], stage[i+1][WIDTH-1:WIDTH-(2**i)]}) when WIDTH=8:
    // s3 = in                   76543210
    // s2 = {s3[3:0],s3[7:4]} -> 32107654
    // s1 = {s2[5:0],s3[7:6]} -> 10765432
    // s0 = {s1[6:0],s1[7:7]} -> 07654321

    wire [WIDTH-1:0] stage[SHIFT_WIDTH:0];
    assign stage[SHIFT_WIDTH] = in;
    assign res = stage[0];

    generate //: stage_select
        for (i = 0; i < SHIFT_WIDTH; i = i + 1)
        begin: stage_mux
            Mux2 #(.WIDTH(WIDTH)) mux(
               .in2(stage[i+1]),
               .in1({stage[i+1][WIDTH-(2**i)-1:0], stage[i+1][WIDTH-1:WIDTH-(2**i)]}),
               .sel(shift[i]), // i-th bit of shift
               .out(stage[i])  // i-th stage either copy of prev. stage
            );
        end: stage_mux
    endgenerate //: stage_select


endmodule: BarrelShifter

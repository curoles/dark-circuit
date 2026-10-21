/* Barrel shifter, made of gates.
 *
 * Shifts or rotates in by shift positions, left or right, combinational.
 * Shift fills vacated bits with shift_in_bit: 0 for logical shift,
 * in[WIDTH-1] for arithmetic shift right.
 * WIDTH is 2 or more, not only a power of 2: rotate by shift >= WIDTH rotates
 * by shift % WIDTH, shift by shift >= WIDTH gives all shift_in_bit.
 *
 * Stages only shift or rotate LEFT. Right is done by reversing the bit order of
 * the input and of the result: reverse, shift left, reverse is shift right, and
 * fill bits that enter at the low end of the reversed vector end up at the high end.
 * Stage i shifts by 2**i when shift[i] is 1, otherwise passes; shift 5 = 4 + 1
 * is done by stages 2 and 0. New low bits of stage i are shift_in_bit (shift)
 * or the top 2**i bits of the stage input (rotate). Example WIDTH=8, rotate by 7:
 *   stage[0] = in              76543210
 *   stage[1] = rotate 1     -> 65432107
 *   stage[2] = rotate 2     -> 43210765
 *   stage[3] = rotate 4     -> 07654321
 *
 * @author    Igor Lesik
 * @copyright 2019-2020 Igor Lesik, MIT License
 */
module BarrelShifter #(
    parameter  WIDTH       = 64,
    localparam SHIFT_WIDTH = $clog2(WIDTH)
)(
    input  wire [WIDTH-1:0]       in,
    input  wire                   shift_in_bit,  // fills vacated bits of shift
    input  wire [SHIFT_WIDTH-1:0] shift,         // number of positions
    input  wire                   shift_rotate,  // 1 shift, 0 rotate
    input  wire                   left_right,    // 1 left, 0 right
    output wire [WIDTH-1:0]       out
);
    wire [WIDTH-1:0] ain;                    // in, reversed for right
    wire [WIDTH-1:0] res;                    // ain shifted or rotated left
    wire [WIDTH-1:0] stage [SHIFT_WIDTH+1];  // stage[i+1] is stage[i] after stage i

    for (genvar i = 0; i < WIDTH; i++) begin : g_reverse
        Mux2 #(1) u_mux2_in (.in0(in[WIDTH-1-i]),  .in1(in[i]),  .sel(left_right), .out(ain[i]));
        Mux2 #(1) u_mux2_out(.in0(res[WIDTH-1-i]), .in1(res[i]), .sel(left_right), .out(out[i]));
    end

    assign stage[0] = ain;
    for (genvar i = 0; i < SHIFT_WIDTH; i++) begin : g_stage
        localparam N = 1 << i;  // shift of this stage
        wire [N-1:0] low;       // new low bits: fill for shift, top bits for rotate
        Mux2 #(N)     u_mux2_low(.in0(stage[i][WIDTH-1 -: N]), .in1({N{shift_in_bit}}),
                                 .sel(shift_rotate), .out(low));
        Mux2 #(WIDTH) u_mux2    (.in0(stage[i]), .in1({stage[i][WIDTH-N-1:0], low}),
                                 .sel(shift[i]), .out(stage[i+1]));
    end
    assign res = stage[SHIFT_WIDTH];

endmodule

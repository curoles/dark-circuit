/* Barrel shifter, behavioral.
 *
 * Author: Igor Lesik 2019-2020
 *
 * Shifts or rotates in by shift positions, left or right, combinational.
 * Shift fills vacated bits with shift_in_bit: 0 for logical shift,
 * in[WIDTH-1] for arithmetic shift right.
 * WIDTH is 2 or more, not only a power of 2: rotate by shift >= WIDTH rotates
 * by shift % WIDTH, shift by shift >= WIDTH gives all shift_in_bit.
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
    output reg  [WIDTH-1:0]       out
);
    localparam [WIDTH-1:0] ONES = {WIDTH{1'b1}};

    wire [WIDTH-1:0] fill;
    int              rot;  // rotate by shift is rotate by shift % WIDTH

    assign fill = {WIDTH{shift_in_bit}};
    assign rot  = int'(shift) % WIDTH;

    always_comb
        if (shift_rotate) out = left_right ? (in << shift) | (fill & ~(ONES << shift))
                                           : (in >> shift) | (fill & ~(ONES >> shift));
        else              out = left_right ? (in << rot) | (in >> (WIDTH - rot))
                                           : (in >> rot) | (in << (WIDTH - rot));

endmodule

module TbTop (

);

    localparam VALUE_WIDTH = 64;
    localparam SHIFT_WIDTH = 6;

    bit  [VALUE_WIDTH-1:0] in_val;
    bit  [SHIFT_WIDTH-1:0] shift_amount;
    bit                    shift_rotate;
    bit                    left_right;
    wire [VALUE_WIDTH-1:0] out_val;

    BarrelShifter#(VALUE_WIDTH, SHIFT_WIDTH) shifter(
        .in(in_val),
        .shift(shift_amount),
        .shift_rotate(shift_rotate),
        .left_right(left_right),
        .out(out_val)
    );

endmodule: TbTop

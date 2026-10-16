/* Test of BarrelShifter block, behave or struct version.
 *
 * Exhaustive: every input, shift, left/right, shift/rotate and shift_in_bit,
 * for WIDTH=8 and for WIDTH=5 (not a power of 2, shift 5..7 is beyond WIDTH).
 * Expected value is made bit by bit: out[j] is in[j-s] for left, in[j+s] for right,
 * shift_in_bit when that bit is outside of in (shift), index modulo WIDTH (rotate).
 * Stops at the first mismatch with $fatal.
 */
module TbBarrelShifter;
    localparam W8 = 8;
    localparam W5 = 5;

    reg  [W8-1:0] in8;
    reg  [2:0]    shift8;
    wire [W8-1:0] out8;
    reg  [W5-1:0] in5;
    reg  [2:0]    shift5;
    wire [W5-1:0] out5;
    reg           shift_in_bit;
    reg           shift_rotate;
    reg           left_right;
    reg  [W8-1:0] exp8;
    // Function returns W8 bits, only the low W5 are used.
    /* verilator lint_off UNUSEDSIGNAL */
    reg  [W8-1:0] exp5;
    /* verilator lint_on UNUSEDSIGNAL */
    integer i;

    BarrelShifter #(.WIDTH(W8)) u_barrel_shifter_8(.in(in8), .shift_in_bit(shift_in_bit), .shift(shift8),
        .shift_rotate(shift_rotate), .left_right(left_right), .out(out8));
    BarrelShifter #(.WIDTH(W5)) u_barrel_shifter_5(.in(in5), .shift_in_bit(shift_in_bit), .shift(shift5),
        .shift_rotate(shift_rotate), .left_right(left_right), .out(out5));

    // Expected out of WIDTH w bits, in and out are in the low w bits.
    function automatic [W8-1:0] expected(input integer w, input [W8-1:0] x, input integer s,
                                         input fill, input shift_op, input left);
        integer j;
        integer src;
        begin
            expected = 0;
            for (j = 0; j < w; j = j + 1) begin
                src = left ? j - s : j + s;
                if (shift_op)
                    expected[j] = (src >= 0 && src < w) ? x[src] : fill;
                else
                    expected[j] = x[((src % w) + w) % w];
            end
        end
    endfunction

    initial begin
        // {shift_in_bit, shift_rotate, left_right, shift, in}: 3 + 3 + 8 bits.
        for (i = 0; i < (1 << 14); i = i + 1) begin
            {shift_in_bit, shift_rotate, left_right} = i[13:11];
            shift8 = i[10:8];
            in8    = i[7:0];
            shift5 = i[10:8];
            in5    = i[4:0];
            exp8 = expected(W8, in8, int'(shift8), shift_in_bit, shift_rotate, left_right);
            exp5 = expected(W5, {3'b0, in5}, int'(shift5), shift_in_bit, shift_rotate, left_right);
            #1;
            if (out8 !== exp8)
                $fatal(1, "BarrelShifter 8: in=%b shift=%0d shift_rotate=%b left_right=%b shift_in_bit=%b got %b, expected %b",
                       in8, shift8, shift_rotate, left_right, shift_in_bit, out8, exp8);
            if (out5 !== exp5[W5-1:0])
                $fatal(1, "BarrelShifter 5: in=%b shift=%0d shift_rotate=%b left_right=%b shift_in_bit=%b got %b, expected %b",
                       in5, shift5, shift_rotate, left_right, shift_in_bit, out5, exp5[W5-1:0]);
        end

        $display("PASS");
        $finish;
    end
endmodule

/* Test of PackedMinMax (WIDTH 32) on PackedAdd's a - b, as its users chain them: lanes of 8,
 * 16 and 32 bits, minimum and maximum, signed and unsigned.
 *
 * Per lane, by meaning: the smaller or the larger of the lane's values of a and b (signed or
 * unsigned). Lanes of 8 bits: exhaustive, every pair of bytes in every lane (a different
 * pair in each lane at once), all four operations. Lanes of 16 and 32 bits: edge values (0,
 * 1, the largest positive, the smallest negative, all ones) in every pair, and random words.
 * Stops at the first mismatch with $fatal.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module TbPackedMinMax;
    import PackedPkg::*;

    localparam int WIDTH        = 32;
    localparam int BYTES        = WIDTH / 8;
    localparam int RANDOM_CASES = 30000;

    logic [WIDTH-1:0] a;
    logic [WIDTH-1:0] b;
    logic             is_unsigned;
    logic             max;
    lane_e            lane;
    // PackedAdd's sum and overflows are not used by PackedMinMax.
    /* verilator lint_off UNUSEDSIGNAL */
    logic [WIDTH-1:0] sum;
    logic [BYTES-1:0] ov;
    /* verilator lint_on UNUSEDSIGNAL */
    logic [BYTES-1:0] co;
    logic [WIDTH-1:0] result;

    PackedAdd #(.WIDTH(WIDTH)) u_packed_add(.a, .b, .sub(1'b1), .lane, .sum, .co, .ov);
    PackedMinMax #(.WIDTH(WIDTH)) u_packed_min_max(.a, .b, .co, .is_unsigned, .max, .lane,
                                                   .result);

    function automatic int bits_of(input lane_e l);
        case (l)
            LANE_8:  return 8;
            LANE_16: return 16;
            default: return 32;
        endcase
    endfunction

    task automatic check;
        int          lb;
        logic [31:0] mask;
        logic [31:0] xu;        // the lane's bits
        logic [31:0] yu;
        longint      x;
        longint      y;
        longint      hi;        // the largest signed value of the lane
        logic [31:0] exp_lane;
        #1;
        lb   = bits_of(lane);
        mask = (lb == 32) ? '1 : (32'(1) << lb) - 1;
        hi   = (longint'(1) << (lb - 1)) - 1;
        for (int j = 0; j < WIDTH / lb; j++) begin
            xu = (a >> (j * lb)) & mask;
            yu = (b >> (j * lb)) & mask;
            x  = longint'(xu);
            y  = longint'(yu);
            if (!is_unsigned) begin     // the lane's value as a signed number
                if (x > hi) x -= longint'(1) << lb;
                if (y > hi) y -= longint'(1) << lb;
            end
            exp_lane = 32'(max ? ((x > y) ? x : y) : ((x < y) ? x : y)) & mask;
            if (((result >> (j * lb)) & mask) !== exp_lane)
                $fatal(1, "PackedMinMax lane %0d of %0d bits: %s%s(%0d, %0d) -> %h, expected %h",
                       j, lb, max ? "max" : "min", is_unsigned ? "u" : "", x, y,
                       (result >> (j * lb)) & mask, exp_lane);
        end
    endtask

    initial begin
        logic [31:0] edges [5];
        // Lanes of 8 bits: every pair in every lane at once.
        lane = LANE_8;
        for (int m = 0; m < 4; m++)
            for (int x = 0; x < 256; x++)
                for (int y = 0; y < 256; y++) begin
                    {is_unsigned, max} = 2'(m);
                    for (int j = 0; j < BYTES; j++) begin
                        a[8*j +: 8] = 8'(x + 85 * j);
                        b[8*j +: 8] = 8'(y) ^ 8'(8'h5b * j);
                    end
                    check();
                end
        // Lanes of 16 and 32 bits: edge values, then random words.
        for (int l = 1; l < 3; l++) begin
            int lb;
            lane = lane_e'(l);
            lb   = bits_of(lane);
            edges[0] = 0;
            edges[1] = 1;
            edges[2] = (32'(1) << (lb - 1)) - 1;    // the largest positive
            edges[3] = 32'(1) << (lb - 1);          // the smallest negative
            edges[4] = (lb == 32) ? '1 : (32'(1) << lb) - 1;
            for (int m = 0; m < 4; m++)
                for (int i = 0; i < 5; i++)
                    for (int k = 0; k < 5; k++) begin
                        {is_unsigned, max} = 2'(m);
                        a = '0;
                        b = '0;
                        for (int j = 0; j < WIDTH / lb; j++) begin
                            a |= edges[i] << (j * lb);
                            b |= edges[(k + j) % 5] << (j * lb);
                        end
                        check();
                    end
            for (int n = 0; n < RANDOM_CASES; n++) begin
                a           = $urandom();
                b           = $urandom();
                is_unsigned = 1'($urandom() % 2);
                max         = 1'($urandom() % 2);
                check();
            end
        end
        $display("PASS");
        $finish;
    end
endmodule

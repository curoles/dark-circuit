/* Test of PackedSaturate (WIDTH 32) on PackedAdd, as its users chain them, and of
 * PackedPkg::lane_tops: lanes of 8, 16 and 32 bits, add and subtract, signed and unsigned.
 *
 * Per lane, by meaning: the true result x + y or x - y of the lane's values (signed or
 * unsigned) clamped to the lane's range (signed -2^(L-1) .. 2^(L-1) - 1, unsigned
 * 0 .. 2^L - 1); sat is 1 when some lane was clamped. lane_tops: byte k is 1 when it is its
 * lane's top byte. Lanes of 8 bits: exhaustive, every pair of bytes in every lane (a
 * different pair in each lane at once), add and subtract, signed and unsigned; sat then
 * comes from several lanes at once, so also every pair in lane 0 alone (the others 0 + 0).
 * Lanes of 16 and 32 bits: edge values (0, 1, the largest positive, the smallest negative,
 * all ones) in every pair, and random words. Stops at the first mismatch with $fatal.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module TbPackedSaturate;
    import PackedPkg::*;

    localparam int WIDTH        = 32;
    localparam int BYTES        = WIDTH / 8;
    localparam int RANDOM_CASES = 30000;

    logic [WIDTH-1:0] a;
    logic [WIDTH-1:0] b;
    logic             sub;
    logic             is_unsigned;
    lane_e            lane;
    logic [WIDTH-1:0] sum;
    logic [BYTES-1:0] co;
    logic [BYTES-1:0] ov;
    logic [WIDTH-1:0] result;
    logic             sat;

    PackedAdd #(.WIDTH(WIDTH)) u_packed_add(.a, .b, .sub, .lane, .sum, .co, .ov);
    PackedSaturate #(.WIDTH(WIDTH)) u_packed_saturate(
        .a, .sum, .co, .ov, .sub, .is_unsigned, .lane, .result, .sat);

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
        longint      r;
        longint      lo;
        longint      hi;
        logic [31:0] exp_lane;
        logic        exp_sat;
        logic [7:0]  tops;
        #1;
        lb      = bits_of(lane);
        mask    = (lb == 32) ? '1 : (32'(1) << lb) - 1;
        lo      = is_unsigned ? 0 : -(longint'(1) << (lb - 1));
        hi      = is_unsigned ? (longint'(1) << lb) - 1 : (longint'(1) << (lb - 1)) - 1;
        exp_sat = 1'b0;
        for (int j = 0; j < WIDTH / lb; j++) begin
            xu = (a >> (j * lb)) & mask;
            yu = (b >> (j * lb)) & mask;
            x  = longint'(xu);
            y  = longint'(yu);
            if (!is_unsigned) begin     // the lane's value as a signed number
                if (x > hi) x -= longint'(1) << lb;
                if (y > hi) y -= longint'(1) << lb;
            end
            r = sub ? x - y : x + y;
            if (r < lo || r > hi)
                exp_sat = 1'b1;
            r = (r < lo) ? lo : (r > hi) ? hi : r;
            exp_lane = 32'(r) & mask;
            if (((result >> (j * lb)) & mask) !== exp_lane)
                $fatal(1, "PackedSaturate lane %0d of %0d bits (%s): %0d %s %0d -> %h, expected %h",
                       j, lb, is_unsigned ? "unsigned" : "signed", x, sub ? "-" : "+", y,
                       (result >> (j * lb)) & mask, exp_lane);
        end
        if (sat !== exp_sat)
            $fatal(1, "PackedSaturate lanes of %0d bits (%s): %h %s %h: sat %b, expected %b",
                   lb, is_unsigned ? "unsigned" : "signed", a, sub ? "-" : "+", b, sat, exp_sat);
        tops = lane_tops(lane);
        for (int k = 0; k < 8; k++)
            if (tops[k] !== ((k + 1) * 8 % lb == 0))
                $fatal(1, "lane_tops byte %0d (lanes of %0d): %b", k, lb, tops[k]);
    endtask

    initial begin
        logic [31:0] edges [5];
        // Lanes of 8 bits: every pair in every lane at once, then in lane 0 alone.
        lane = LANE_8;
        for (int m = 0; m < 4; m++)
            for (int x = 0; x < 256; x++)
                for (int y = 0; y < 256; y++) begin
                    {is_unsigned, sub} = 2'(m);
                    for (int j = 0; j < BYTES; j++) begin
                        a[8*j +: 8] = 8'(x + 85 * j);
                        b[8*j +: 8] = 8'(y) ^ 8'(8'h5b * j);
                    end
                    check();
                    a = 32'(8'(x));
                    b = 32'(8'(y));
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
                        {is_unsigned, sub} = 2'(m);
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
                sub         = 1'($urandom() % 2);
                is_unsigned = 1'($urandom() % 2);
                check();
            end
        end
        $display("PASS");
        $finish;
    end
endmodule

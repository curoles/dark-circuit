/* Test of PackedAdd (WIDTH 32) and PackedPkg's helpers: lanes of 8, 16 and 32 bits, add and
 * subtract.
 *
 * Per lane, by meaning: the sum wraps in the lane (x + y or x - y mod 2^L); the lane's carry
 * out (co at its top byte) is the carry of x + y, for x - y 1 when x >= y unsigned; its
 * signed overflow (ov at its top byte) is the result's sign differing from the sign that
 * x and y (for x - y: x and -y) share. Per byte: co and ov at every byte's top bit, also
 * inside a lane, against a walk of the bits from the lane's low bit (the carry in sub there,
 * b inverted for a subtraction). lane_broadcast of co and ov: every byte gets its lane's
 * top byte's flag. Lanes of 8 bits: exhaustive, every pair of bytes in every lane (a
 * different pair in each lane at once), add and subtract. Lanes of 16 and 32 bits: edge
 * values (0, 1, the largest positive, the smallest negative, all ones) in every pair, and
 * random words. Stops at the first mismatch with $fatal.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module TbPackedAdd;
    import PackedPkg::*;

    localparam int WIDTH        = 32;
    localparam int BYTES        = WIDTH / 8;
    localparam int RANDOM_CASES = 30000;

    logic [WIDTH-1:0] a;
    logic [WIDTH-1:0] b;
    logic             sub;
    lane_e            lane;
    logic [WIDTH-1:0] sum;
    logic [BYTES-1:0] co;
    logic [BYTES-1:0] ov;

    PackedAdd #(.WIDTH(WIDTH)) u_packed_add(.a, .b, .sub, .lane, .sum, .co, .ov);

    function automatic int bits_of(input lane_e l);
        case (l)
            LANE_8:  return 8;
            LANE_16: return 16;
            default: return 32;
        endcase
    endfunction

    task automatic check;
        int          lb;
        logic [31:0] x;
        logic [31:0] y;
        logic [31:0] y_neg;     // ~y in the lane
        logic [32:0] full;
        logic [31:0] s;
        logic [31:0] mask;
        logic        lane_co;
        logic        lane_ov;
        logic [31:0] c;         // the walk: carry out of every bit, within its lane
        logic        cin;
        logic [7:0]  co_b;
        logic [7:0]  ov_b;
        // A byte's index: only its low bits are used.
        /* verilator lint_off UNUSEDSIGNAL */
        int          top;
        /* verilator lint_on UNUSEDSIGNAL */
        #1;
        lb   = bits_of(lane);
        mask = (lb == 32) ? '1 : (32'(1) << lb) - 1;
        // Per lane, by meaning.
        for (int j = 0; j < WIDTH / lb; j++) begin
            x    = (a >> (j * lb)) & mask;
            y    = (b >> (j * lb)) & mask;
            y_neg = ~y & mask;
            full  = sub ? 33'(x) + 33'(y_neg) + 33'd1 : 33'(x) + 33'(y);
            s    = full[31:0] & mask;
            lane_co = full[lb];
            if (sub)
                lane_ov = (x[lb-1] != y[lb-1]) && (s[lb-1] != x[lb-1]);
            else
                lane_ov = (x[lb-1] == y[lb-1]) && (s[lb-1] != x[lb-1]);
            top = (j + 1) * lb / 8 - 1;
            if (((sum >> (j * lb)) & mask) !== s || co[top] !== lane_co || ov[top] !== lane_ov)
                $fatal(1, "PackedAdd lane %0d of %0d bits: %h %s %h -> %h co %b ov %b, expected %h co %b ov %b",
                       j, lb, x, sub ? "-" : "+", y, (sum >> (j * lb)) & mask, co[top], ov[top],
                       s, lane_co, lane_ov);
        end
        // Per byte: the walk of the bits.
        for (int i = 0; i < WIDTH; i++) begin
            cin  = (i % lb == 0) ? sub : c[i-1];
            c[i] = (a[i] & (b[i] ^ sub)) | (a[i] & cin) | ((b[i] ^ sub) & cin);
        end
        for (int k = 0; k < BYTES; k++)
            if (co[k] !== c[8*k+7] || ov[k] !== (c[8*k+7] ^ c[8*k+6]))
                $fatal(1, "PackedAdd byte %0d (lanes of %0d): %h %s %h: co %b ov %b, expected %b %b",
                       k, lb, a, sub ? "-" : "+", b, co[k], ov[k], c[8*k+7], c[8*k+7] ^ c[8*k+6]);
        // lane_broadcast: every byte gets its lane's top byte's flag.
        co_b = lane_broadcast(8'(co), lane);
        ov_b = lane_broadcast(8'(ov), lane);
        for (int k = 0; k < BYTES; k++) begin
            top = (k * 8 / lb + 1) * lb / 8 - 1;
            if (co_b[k] !== co[top] || ov_b[k] !== ov[top])
                $fatal(1, "lane_broadcast byte %0d (lanes of %0d): co %b ov %b, expected %b %b",
                       k, lb, co_b[k], ov_b[k], co[top], ov[top]);
        end
    endtask

    initial begin
        logic [31:0] edges [5];
        // Lanes of 8 bits: every pair in every lane.
        lane = LANE_8;
        for (int s = 0; s < 2; s++)
            for (int x = 0; x < 256; x++)
                for (int y = 0; y < 256; y++) begin
                    sub = s[0];
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
            for (int s = 0; s < 2; s++)
                for (int i = 0; i < 5; i++)
                    for (int k = 0; k < 5; k++) begin
                        sub = s[0];
                        a   = '0;
                        b   = '0;
                        for (int j = 0; j < WIDTH / lb; j++) begin
                            a |= edges[i] << (j * lb);
                            b |= edges[(k + j) % 5] << (j * lb);
                        end
                        check();
                    end
            for (int n = 0; n < RANDOM_CASES; n++) begin
                a   = $urandom();
                b   = $urandom();
                sub = 1'($urandom() % 2);
                check();
            end
        end
        $display("PASS");
        $finish;
    end
endmodule

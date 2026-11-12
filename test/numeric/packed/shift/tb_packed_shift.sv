/* Test of PackedShift (WIDTH 32): lanes of 8, 16 and 32 bits, every amount 0 to 31, left,
 * logical right and arithmetic right (arith with a left shift: ignored).
 *
 * Per lane, by meaning: the lane's value shifted as a number of its width, as RISC-V P
 * defines it: left (v << amount) and logical right (v >> amount) of the zero-extended value,
 * arithmetic right of the sign-extended value, then the lane's low bits; amount >= the lane
 * width gives 0, or the sign everywhere. Lanes of 8 bits: exhaustive, every byte in every
 * lane (a different byte in each lane at once) with every amount and all four controls.
 * Lanes of 16 and 32 bits: edge values (0, 1, the largest positive, the smallest negative,
 * all ones, 0x5555...) with every amount, and random words. Stops at the first mismatch with
 * $fatal.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module TbPackedShift;
    import PackedPkg::*;

    localparam int WIDTH        = 32;
    localparam int BYTES        = WIDTH / 8;
    localparam int RANDOM_CASES = 30000;

    logic [WIDTH-1:0] in;
    logic [4:0]       amount;
    logic             left;
    logic             arith;
    lane_e            lane;
    logic [WIDTH-1:0] result;

    PackedShift #(.WIDTH(WIDTH)) u_packed_shift(.in, .amount, .left, .arith, .lane, .result);

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
        logic [31:0] vu;        // the lane's bits
        longint      v;
        logic [31:0] exp_lane;
        #1;
        lb   = bits_of(lane);
        mask = (lb == 32) ? '1 : (32'(1) << lb) - 1;
        for (int j = 0; j < WIDTH / lb; j++) begin
            vu = (in >> (j * lb)) & mask;
            v  = longint'(vu);
            if (left)
                exp_lane = 32'(v << amount) & mask;
            else if (arith) begin
                if (vu[lb-1]) v -= longint'(1) << lb;   // sign-extended
                exp_lane = 32'(v >>> amount) & mask;
            end else
                exp_lane = 32'(v >> amount) & mask;
            if (((result >> (j * lb)) & mask) !== exp_lane)
                $fatal(1, "PackedShift lane %0d of %0d bits: %h %s %0d -> %h, expected %h",
                       j, lb, vu, left ? "<<" : arith ? ">>>" : ">>", amount,
                       (result >> (j * lb)) & mask, exp_lane);
        end
    endtask

    initial begin
        logic [31:0] edges [6];
        // Lanes of 8 bits: every byte in every lane, every amount, all controls.
        lane = LANE_8;
        for (int m = 0; m < 4; m++)
            for (int s = 0; s < 32; s++)
                for (int x = 0; x < 256; x++) begin
                    {left, arith} = 2'(m);
                    amount        = 5'(s);
                    for (int j = 0; j < BYTES; j++)
                        in[8*j +: 8] = 8'(x + 85 * j);
                    check();
                end
        // Lanes of 16 and 32 bits: edge values with every amount, then random words.
        for (int l = 1; l < 3; l++) begin
            int lb;
            lane = lane_e'(l);
            lb   = bits_of(lane);
            edges[0] = 0;
            edges[1] = 1;
            edges[2] = (32'(1) << (lb - 1)) - 1;    // the largest positive
            edges[3] = 32'(1) << (lb - 1);          // the smallest negative
            edges[4] = (lb == 32) ? '1 : (32'(1) << lb) - 1;
            edges[5] = 32'h5555_5555 & edges[4];
            for (int m = 0; m < 4; m++)
                for (int s = 0; s < 32; s++)
                    for (int i = 0; i < 6; i++) begin
                        {left, arith} = 2'(m);
                        amount        = 5'(s);
                        in = '0;
                        for (int j = 0; j < WIDTH / lb; j++)
                            in |= edges[(i + j) % 6] << (j * lb);
                        check();
                    end
            for (int n = 0; n < RANDOM_CASES; n++) begin
                in     = $urandom();
                amount = 5'($urandom());
                left   = 1'($urandom() % 2);
                arith  = 1'($urandom() % 2);
                check();
            end
        end
        $display("PASS");
        $finish;
    end
endmodule

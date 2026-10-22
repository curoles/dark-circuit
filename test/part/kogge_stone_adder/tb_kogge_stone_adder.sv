/* Test of KoggeStoneAdder: {co, sum} = in1 + in2 + ci for WIDTH 1, 4, 5 and 64.
 *
 * The four adders get the same operands (the low bits for the narrow ones) and are
 * compared with +. Exhaustive for the narrow ones: every value of the low LOW_BITS bits
 * of in1 and in2 and of ci, with random upper bits. Then 64-bit corner cases (carries
 * through every bit, the longest propagate) and random operands. Icarus simulates the
 * gate-level adders about a thousand times slower than Verilator: fewer cases there.
 * Stops at the first mismatch with $fatal.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module TbKoggeStoneAdder;
`ifdef VERILATOR
    localparam int LOW_BITS     = 5;        // exhaustive: WIDTH 1, 4 and 5
    localparam int RANDOM_CASES = 100000;
`else
    localparam int LOW_BITS     = 4;        // exhaustive: WIDTH 1 and 4
    localparam int RANDOM_CASES = 500;
`endif

    logic [63:0] a;
    logic [63:0] b;
    logic        ci;
    logic        co1;
    logic [0:0]  sum1;
    logic        co4;
    logic [3:0]  sum4;
    logic        co5;
    logic [4:0]  sum5;
    logic        co64;
    logic [63:0] sum64;

    KoggeStoneAdder #(.WIDTH(1)) u_kogge_stone_adder_1(
        .in1(a[0:0]), .in2(b[0:0]), .ci, .co(co1), .sum(sum1));
    KoggeStoneAdder #(.WIDTH(4)) u_kogge_stone_adder_4(
        .in1(a[3:0]), .in2(b[3:0]), .ci, .co(co4), .sum(sum4));
    KoggeStoneAdder #(.WIDTH(5)) u_kogge_stone_adder_5(
        .in1(a[4:0]), .in2(b[4:0]), .ci, .co(co5), .sum(sum5));
    KoggeStoneAdder u_kogge_stone_adder_64(
        .in1(a), .in2(b), .ci, .co(co64), .sum(sum64));

    // All four adders against + for the current a, b, ci.
    task automatic check();
        #1;
        if ({co1, sum1} !== {1'b0, a[0]} + {1'b0, b[0]} + {1'b0, ci})
            $fatal(1, "WIDTH 1: %b + %b + %b: got %b%b", a[0], b[0], ci, co1, sum1);
        if ({co4, sum4} !== {1'b0, a[3:0]} + {1'b0, b[3:0]} + {4'b0, ci})
            $fatal(1, "WIDTH 4: %h + %h + %b: got %b %h", a[3:0], b[3:0], ci, co4, sum4);
        if ({co5, sum5} !== {1'b0, a[4:0]} + {1'b0, b[4:0]} + {5'b0, ci})
            $fatal(1, "WIDTH 5: %h + %h + %b: got %b %h", a[4:0], b[4:0], ci, co5, sum5);
        if ({co64, sum64} !== {1'b0, a} + {1'b0, b} + {64'b0, ci})
            $fatal(1, "WIDTH 64: %h + %h + %b: got %b %h", a, b, ci, co64, sum64);
    endtask

    task automatic check64(logic [63:0] x, logic [63:0] y, logic z);
        a  = x;
        b  = y;
        ci = z;
        check();
    endtask

    initial begin
        // Narrow widths exhaustive: low LOW_BITS bits of a and b, and ci.
        for (int i = 0; i < 2**(2*LOW_BITS+1); i++) begin
            a               = {$urandom, $urandom};
            b               = {$urandom, $urandom};
            a[LOW_BITS-1:0] = i[LOW_BITS-1:0];
            b[LOW_BITS-1:0] = i[2*LOW_BITS-1:LOW_BITS];
            ci              = i[2*LOW_BITS];
            check();
        end
        // 64 bits: carries through every bit, the longest propagate.
        check64('1, 64'd1, 1'b0);
        check64('1, '0, 1'b1);
        check64('1, '1, 1'b1);
        check64('0, '0, 1'b0);
        check64(64'h5555_5555_5555_5555, 64'haaaa_aaaa_aaaa_aaaa, 1'b1);
        check64(64'h5555_5555_5555_5555, 64'haaaa_aaaa_aaaa_aaaa, 1'b0);
        for (int i = 0; i < RANDOM_CASES; i++)
            check64({$urandom, $urandom}, {$urandom, $urandom}, ($urandom & 1) != 0);
        $finish;
    end

endmodule

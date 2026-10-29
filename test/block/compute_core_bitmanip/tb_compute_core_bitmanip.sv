/* Test of ComputeCoreBitmanip, behave or struct version.
 *
 * Every input goes through all 8 operations. Inputs: 0, all ones, and for every bit b: the
 * one-hot word, its inverse, all ones from b up and all ones from b down (every count of CLZ,
 * CTZ, CPOP from 0 to WIDTH); then random words, half of them with random leading or trailing
 * zeros. The model computes differently from the block: the sign extension by an arithmetic
 * shift, CLZ and CTZ by shifting until a one comes out, CPOP by clearing the lowest one. In
 * the end the test checks that every count 0..WIDTH of CLZ, CTZ and CPOP happened. Runs with
 * WIDTH 16, 32, 64; 5000 random words on Verilator, 200 on Icarus. Stops at the first
 * mismatch with $fatal.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module TbComputeCoreBitmanipCheck import ComputeCoreBitmanipPkg::*; #(
    parameter WIDTH = 32
)(
    output logic done
);
`ifdef VERILATOR
    localparam N_RANDOM = 5000;
`else
    localparam N_RANDOM = 200;
`endif

    typedef logic [WIDTH-1:0] word_t;
    localparam word_t ONES = '1;

    logic   [WIDTH-1:0] in;
    bm_op_e             op;
    wire    [WIDTH-1:0] out;

    logic   [WIDTH:0]   seen_clz;   // coverage: counts 0..WIDTH that happened
    logic   [WIDTH:0]   seen_ctz;
    logic   [WIDTH:0]   seen_cpop;
    integer             seed;
    // Random word, only some of its bits are used.
    /* verilator lint_off UNUSEDSIGNAL */
    logic   [31:0]      rnd;
    /* verilator lint_on UNUSEDSIGNAL */

    ComputeCoreBitmanip #(.WIDTH(WIDTH)) u_compute_core_bitmanip(.in, .op, .out);

    function automatic word_t model(input word_t x, input bm_op_e o);
        word_t v;
        word_t r;
        int    n;
        r = '0;
        n = 0;
        v = x;
        case (o)
            BM_SEXT_B: r = word_t'($signed(x << (WIDTH - 8)) >>> (WIDTH - 8));
            BM_SEXT_H: r = word_t'($signed(x << (WIDTH - 16)) >>> (WIDTH - 16));
            BM_ZEXT_H: r = x & word_t'(16'hffff);
            BM_ORC_B:
                for (int i = 0; i < WIDTH / 8; i++)
                    if (((x >> (8 * i)) & word_t'(8'hff)) != '0)
                        r = r | (word_t'(8'hff) << (8 * i));
            BM_REV8:
                for (int i = 0; i < WIDTH / 8; i++) begin
                    r = (r << 8) | (v & word_t'(8'hff));
                    v = v >> 8;
                end
            BM_CLZ: begin
                while (n < WIDTH && !v[WIDTH-1]) begin
                    v = v << 1;
                    n++;
                end
                r = word_t'(n);
            end
            BM_CTZ: begin
                while (n < WIDTH && !v[0]) begin
                    v = v >> 1;
                    n++;
                end
                r = word_t'(n);
            end
            default: begin                  // BM_CPOP
                while (v != '0) begin
                    v = v & (v - 1'b1);
                    n++;
                end
                r = word_t'(n);
            end
        endcase
        return r;
    endfunction

    // A random word; with kind 1 or 2 its high or low amount % WIDTH bits are cleared.
    function automatic word_t random_word(input logic [1:0] kind, input logic [7:0] amount);
        word_t x;
        x = '0;
        for (int i = 0; i < WIDTH; i += 16)
            x = word_t'({x, 16'($random(seed))});  // shift in 16 random bits
        case (kind)
            2'd1:    x = x >> (amount % WIDTH);
            2'd2:    x = x << (amount % WIDTH);
            default: ;
        endcase
        return x;
    endfunction

    // All 8 operations on x.
    task automatic check_all(input word_t x);
        word_t exp;
        for (int k = 0; k < 8; k++) begin
            op = bm_op_e'(k);
            in = x;
            #1;
            exp = model(x, op);
            if (out !== exp)
                $fatal(1, "ComputeCoreBitmanip %0d: op=%s in=%h got %h, expected %h",
                       WIDTH, op.name(), x, out, exp);
            case (op)
                BM_CLZ:  seen_clz[exp[$clog2(WIDTH):0]]  = 1'b1;
                BM_CTZ:  seen_ctz[exp[$clog2(WIDTH):0]]  = 1'b1;
                BM_CPOP: seen_cpop[exp[$clog2(WIDTH):0]] = 1'b1;
                default: ;
            endcase
        end
    endtask

    initial begin
        done      = 1'b0;
        seen_clz  = '0;
        seen_ctz  = '0;
        seen_cpop = '0;
        seed      = WIDTH;
        check_all('0);
        check_all(ONES);
        for (int b = 0; b < WIDTH; b++) begin
            check_all(word_t'(1) << b);
            check_all(~(word_t'(1) << b));
            check_all(ONES << b);
            check_all(ONES >> b);
        end
        for (int i = 0; i < N_RANDOM; i++) begin
            rnd = $random(seed);
            check_all(random_word(rnd[1:0], rnd[15:8]));
        end
        if (!(&seen_clz) || !(&seen_ctz) || !(&seen_cpop))
            $fatal(1, "ComputeCoreBitmanip %0d: a count did not happen: CLZ %b, CTZ %b, CPOP %b",
                   WIDTH, seen_clz, seen_ctz, seen_cpop);
        done = 1'b1;
    end
endmodule

module TbComputeCoreBitmanip;
    wire done16;
    wire done32;
    wire done64;

    TbComputeCoreBitmanipCheck #(.WIDTH(16)) u_check_16(.done(done16));
    TbComputeCoreBitmanipCheck #(.WIDTH(32)) u_check_32(.done(done32));
    TbComputeCoreBitmanipCheck #(.WIDTH(64)) u_check_64(.done(done64));

    initial begin
        wait (done16 && done32 && done64);
        $finish;
    end
endmodule

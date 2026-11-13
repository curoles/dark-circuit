/* Test of PackedMul (WIDTH 32), STAGES 0 and 1: every lane's product in the product modes,
 * the group's dot product with and without the accumulator in the dot modes, all sign
 * modes.
 *
 * By meaning, on STAGES 0: a lane's product is the product of its operands as numbers
 * (16 x 16, or the byte pair of the mode: al*bl, ah*bh, al*bh), each signed or unsigned by
 * its flag, exact in 32 bits; the dot product is the sum of the four byte products al*bl +
 * ah*bh of both lanes (MUL_DOT_B) or of the two lanes' 16 x 16 products (MUL_DOT_H), plus acc
 * when acc_en, modulo 2^32; with round_en (a random position, in every case) the products
 * have 1 << round_pos added, the dot products not. STAGES 1, streaming: an operation
 * enters every clock, and one
 * clock later, with the next operation's inputs already applied, out_valid is 1 and the
 * result equals STAGES 0's for that operation (so nothing after the register reads the
 * inputs). Byte modes and MUL_DOT_B: each byte of a runs through all values and each byte
 * of b with it (by different offsets), all sign modes, a random accumulator; b's values are
 * every byte with +effort=1 (exhaustive: every pair in every byte position), else 16 of them
 * (0, 1, 2, 0x7e, 0x7f, 0x80, 0x81, 0xfe, 0xff, 0x55, 0xaa and five random). MUL_16 and
 * MUL_DOT_H: edge values (0, 1, the largest positive, the smallest negative, all ones) in
 * every pair and sign mode, with the largest accumulators; random words in all modes. Stops
 * at the first mismatch with $fatal.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module TbPackedMul;
    import PackedPkg::*;

    localparam int WIDTH        = 32;
    localparam int RANDOM_CASES = 30000;

    logic               clk;
    logic               rst_n;
    logic               in_valid;
    logic [WIDTH-1:0]   a;
    logic [WIDTH-1:0]   b;
    logic               a_signed;
    logic               b_signed;
    mul_e               mode;
    logic [WIDTH-1:0]   acc;
    logic               acc_en;
    logic               round_en;
    logic [4:0]         round_pos;
    logic [2*WIDTH-1:0] product;
    logic [WIDTH-1:0]   dot;
    logic [2*WIDTH-1:0] product1;   // STAGES 1
    logic [WIDTH-1:0]   dot1;
    logic               out_valid1;
    // STAGES 0's valid is its input.
    /* verilator lint_off UNUSEDSIGNAL */
    logic               out_valid;
    /* verilator lint_on UNUSEDSIGNAL */

    // The operation before, for STAGES 1: its mode and STAGES 0's results.
    logic               have_prev;
    mul_e               prev_mode;
    logic [2*WIDTH-1:0] prev_product;
    logic [WIDTH-1:0]   prev_dot;

    PackedMul #(.WIDTH(WIDTH), .STAGES(0)) u_packed_mul(
        .clk, .rst_n, .in_valid, .a, .b, .a_signed, .b_signed, .mode, .acc, .acc_en,
        .round_en, .round_pos, .product, .dot, .out_valid);
    PackedMul #(.WIDTH(WIDTH), .STAGES(1)) u_packed_mul_staged(
        .clk, .rst_n, .in_valid, .a, .b, .a_signed, .b_signed, .mode, .acc, .acc_en,
        .round_en, .round_pos, .product(product1), .dot(dot1), .out_valid(out_valid1));

    // An operand as a number: signed (two's complement in w bits) or unsigned.
    function automatic longint value(input logic [15:0] v, input int w, input logic s);
        longint x;
        x = longint'(v);
        if (s && v[w-1])
            x -= longint'(1) << w;
        return x;
    endfunction

    // The product of a byte of x and a byte of y (index 0 low, 1 high).
    function automatic longint byte_product(input logic [15:0] x, input int xi,
                                            input logic [15:0] y, input int yi);
        return value(16'(x[8*xi +: 8]), 8, a_signed) * value(16'(y[8*yi +: 8]), 8, b_signed);
    endfunction

    function automatic logic is_dot(input mul_e m);
        return m == MUL_DOT_B || m == MUL_DOT_H;
    endfunction

    task automatic check;
        logic [15:0] x;
        logic [15:0] y;
        logic [31:0] p;
        logic [31:0] d;
        #1;
        // STAGES 1: the operation before, the inputs already this one's.
        if (have_prev) begin
            if (out_valid1 !== 1'b1)
                $fatal(1, "PackedMul STAGES 1: out_valid %b", out_valid1);
            if (is_dot(prev_mode) ? dot1 !== prev_dot : product1 !== prev_product)
                $fatal(1, "PackedMul STAGES 1, mode %0d: product %h dot %h, expected %h %h",
                       prev_mode, product1, dot1, prev_product, prev_dot);
        end
        // STAGES 0 against the model.
        if (is_dot(mode)) begin
            d = acc_en ? acc : '0;
            for (int k = 0; k < WIDTH / 16; k++) begin
                x = a[16*k +: 16];
                y = b[16*k +: 16];
                if (mode == MUL_DOT_B)
                    d += 32'(byte_product(x, 0, y, 0) + byte_product(x, 1, y, 1));
                else
                    d += 32'(value(x, 16, a_signed) * value(y, 16, b_signed));
            end
            if (dot !== d)
                $fatal(1, "PackedMul dot, mode %0d (signed %b %b): %h . %h + %h (%b) -> %h, expected %h",
                       mode, a_signed, b_signed, a, b, acc, acc_en, dot, d);
        end else
            for (int k = 0; k < WIDTH / 16; k++) begin
                x = a[16*k +: 16];
                y = b[16*k +: 16];
                case (mode)
                    MUL_B00: p = 32'(byte_product(x, 0, y, 0));
                    MUL_B11: p = 32'(byte_product(x, 1, y, 1));
                    MUL_B01: p = 32'(byte_product(x, 0, y, 1));
                    default: p = 32'(value(x, 16, a_signed) * value(y, 16, b_signed));
                endcase
                if (round_en)
                    p += 32'(1) << round_pos;
                if (product[32*k +: 32] !== p)
                    $fatal(1, "PackedMul lane %0d, mode %0d (signed %b %b): %h * %h -> %h, expected %h",
                           k, mode, a_signed, b_signed, x, y, product[32*k +: 32], p);
            end
        // This operation into STAGES 1's register.
        have_prev    = 1'b1;
        prev_mode    = mode;
        prev_product = product;
        prev_dot     = dot;
        clk = 1'b1;
        #1;
        clk = 1'b0;
    endtask

    initial begin
        logic [15:0] edges [5];
        logic [31:0] accs [3];
        logic [7:0]  quick [16];    // b's bytes without +effort=1
        int          effort;        // +effort=<n> (DARK_CIRCUIT_TEST_EFFORT): 1 exhaustive
        if (!$value$plusargs("effort=%d", effort))
            effort = 0;
        quick = '{8'h00, 8'h01, 8'h02, 8'h7e, 8'h7f, 8'h80, 8'h81, 8'hfe, 8'hff, 8'h55, 8'haa,
                  8'h00, 8'h00, 8'h00, 8'h00, 8'h00};
        for (int q = 11; q < 16; q++)
            quick[q] = 8'($urandom());
        clk       = 1'b0;
        rst_n     = 1'b0;
        in_valid  = 1'b1;
        have_prev = 1'b0;
        #1 clk = 1'b1;
        #1 clk = 1'b0;
        rst_n = 1'b1;
        // Byte modes and the byte dot product: every byte of a through every value, b's
        // through every value (+effort=1) or the 16 of quick.
        for (int md = 1; md < 5; md++)
            for (int s = 0; s < 4; s++)
                for (int x = 0; x < 256; x++)
                    for (int yi = 0; yi < (effort >= 1 ? 256 : 16); yi++) begin
                        logic [7:0] y;
                        y    = effort >= 1 ? 8'(yi) : quick[yi];
                        mode = mul_e'(md);
                        {a_signed, b_signed} = 2'(s);
                        for (int j = 0; j < 4; j++) begin
                            a[8*j +: 8] = 8'(x + 85 * j);
                            b[8*j +: 8] = y ^ 8'(8'h5b * j);
                        end
                        acc       = $urandom();
                        acc_en    = 1'($urandom() % 2);
                        round_en  = 1'($urandom() % 2);
                        round_pos = 5'($urandom());
                        check();
                    end
        // MUL_16 and MUL_DOT_H: edge values, with the accumulators that make the sum wrap.
        edges = '{16'h0000, 16'h0001, 16'h7fff, 16'h8000, 16'hffff};
        accs  = '{32'h0000_0000, 32'h7fff_ffff, 32'hffff_ffff};
        for (int md = 0; md < 2; md++)
            for (int s = 0; s < 4; s++)
                for (int i = 0; i < 5; i++)
                    for (int k = 0; k < 5; k++)
                        for (int c = 0; c < 3; c++) begin
                            mode = md == 0 ? MUL_16 : MUL_DOT_H;
                            {a_signed, b_signed} = 2'(s);
                            a      = {edges[(i + 1) % 5], edges[i]};
                            b      = {edges[(k + 2) % 5], edges[k]};
                            acc       = accs[c];
                            acc_en    = 1'b1;
                            round_en  = 1'($urandom() % 2);
                            round_pos = 5'($urandom());
                            check();
                        end
        for (int n = 0; n < RANDOM_CASES; n++) begin
            a        = $urandom();
            b        = $urandom();
            a_signed = 1'($urandom() % 2);
            b_signed = 1'($urandom() % 2);
            mode     = mul_e'($urandom() % 6);
            acc       = $urandom();
            acc_en    = 1'($urandom() % 2);
            round_en  = 1'($urandom() % 2);
            round_pos = 5'($urandom());
            check();
        end
        $display("PASS");
        $finish;
    end
endmodule

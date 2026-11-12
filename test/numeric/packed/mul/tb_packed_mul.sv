/* Test of PackedMul (WIDTH 32): every lane's product in all modes and sign modes.
 *
 * Per lane, by meaning: the product of the lane's operands as numbers (16 x 16, or the byte
 * pair of the mode: al*bl, ah*bh, al*bh), each signed or unsigned by its flag, exact in 32
 * bits. Byte modes: exhaustive, every pair of bytes in every byte position of both lanes
 * (each byte of a and b runs through all values at once, by different offsets), all sign
 * modes. MUL_16: edge values (0, 1, the largest positive, the smallest negative, all ones)
 * in every pair and sign mode, and random words. Stops at the first mismatch with $fatal.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module TbPackedMul;
    import PackedPkg::*;

    localparam int WIDTH        = 32;
    localparam int RANDOM_CASES = 30000;

    logic [WIDTH-1:0]   a;
    logic [WIDTH-1:0]   b;
    logic               a_signed;
    logic               b_signed;
    mul_e               mode;
    logic [2*WIDTH-1:0] product;

    PackedMul #(.WIDTH(WIDTH)) u_packed_mul(.a, .b, .a_signed, .b_signed, .mode, .product);

    // An operand as a number: signed (two's complement in w bits) or unsigned.
    function automatic longint value(input logic [15:0] v, input int w, input logic s);
        longint x;
        x = longint'(v);
        if (s && v[w-1])
            x -= longint'(1) << w;
        return x;
    endfunction

    task automatic check;
        logic [15:0] x;
        logic [15:0] y;
        logic [31:0] p;
        int          w;
        #1;
        for (int k = 0; k < WIDTH / 16; k++) begin
            x = a[16*k +: 16];
            y = b[16*k +: 16];
            case (mode)
                MUL_B00: begin x = {8'b0, x[7:0]};  y = {8'b0, y[7:0]};  w = 8; end
                MUL_B11: begin x = {8'b0, x[15:8]}; y = {8'b0, y[15:8]}; w = 8; end
                MUL_B01: begin x = {8'b0, x[7:0]};  y = {8'b0, y[15:8]}; w = 8; end
                default: w = 16;
            endcase
            p = 32'(value(x, w, a_signed) * value(y, w, b_signed));
            if (product[32*k +: 32] !== p)
                $fatal(1, "PackedMul lane %0d, mode %0d (signed %b %b): %h * %h -> %h, expected %h",
                       k, mode, a_signed, b_signed, a[16*k +: 16], b[16*k +: 16],
                       product[32*k +: 32], p);
        end
    endtask

    initial begin
        logic [15:0] edges [5];
        // Byte modes: every byte of a and b through every value.
        for (int md = 1; md < 4; md++)
            for (int s = 0; s < 4; s++)
                for (int x = 0; x < 256; x++)
                    for (int y = 0; y < 256; y++) begin
                        mode = mul_e'(md);
                        {a_signed, b_signed} = 2'(s);
                        for (int j = 0; j < 4; j++) begin
                            a[8*j +: 8] = 8'(x + 85 * j);
                            b[8*j +: 8] = 8'(y) ^ 8'(8'h5b * j);
                        end
                        check();
                    end
        // MUL_16: edge values, then random words.
        mode  = MUL_16;
        edges = '{16'h0000, 16'h0001, 16'h7fff, 16'h8000, 16'hffff};
        for (int s = 0; s < 4; s++)
            for (int i = 0; i < 5; i++)
                for (int k = 0; k < 5; k++) begin
                    {a_signed, b_signed} = 2'(s);
                    a = {edges[(i + 1) % 5], edges[i]};
                    b = {edges[(k + 2) % 5], edges[k]};
                    check();
                end
        for (int n = 0; n < RANDOM_CASES; n++) begin
            a        = $urandom();
            b        = $urandom();
            a_signed = 1'($urandom() % 2);
            b_signed = 1'($urandom() % 2);
            mode     = mul_e'($urandom() % 4);
            check();
        end
        $display("PASS");
        $finish;
    end
endmodule

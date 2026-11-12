/* Test of MulRows: W 8 with OUT 16 (Int32Mul's case at 8 bits) and OUT 32 (the product
 * extended, as pieces of a wider sum need it), and W 16 with OUT 32.
 *
 * The sum of the rows modulo 2^OUT against a * b of the operands as numbers (signed or
 * unsigned, each), extended to OUT bits. W 8: exhaustive, every pair of operands in all
 * four sign modes, both widths at once. W 16: edge values (0, 1, the largest positive, the
 * smallest negative, all ones) in every pair and mode, and random operands. Stops at the
 * first mismatch with $fatal.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module TbMulRows;
    localparam int RANDOM_CASES = 30000;

    logic [7:0]  a8;
    logic [7:0]  b8;
    logic [15:0] a16;
    logic [15:0] b16;
    logic        a_signed;
    logic        b_signed;
    logic [15:0] rows_8_16 [11];
    logic [31:0] rows_8_32 [11];
    logic [31:0] rows_16_32 [19];

    MulRows #(.W(8), .OUT(16)) u_mul_rows_8_16(
        .a(a8), .b(b8), .a_signed, .b_signed, .rows(rows_8_16));
    MulRows #(.W(8), .OUT(32)) u_mul_rows_8_32(
        .a(a8), .b(b8), .a_signed, .b_signed, .rows(rows_8_32));
    MulRows #(.W(16), .OUT(32)) u_mul_rows_16_32(
        .a(a16), .b(b16), .a_signed, .b_signed, .rows(rows_16_32));

    // An operand as a number: signed (two's complement in w bits) or unsigned.
    function automatic longint value(input logic [15:0] v, input int w, input logic s);
        longint x;
        x = longint'(v);
        if (s && v[w-1])
            x -= longint'(1) << w;
        return x;
    endfunction

    task automatic check8;
        logic [15:0] sum16;
        logic [31:0] sum32;
        logic [31:0] p;
        #1;
        sum16 = '0;
        sum32 = '0;
        for (int r = 0; r < 11; r++) begin
            sum16 += rows_8_16[r];
            sum32 += rows_8_32[r];
        end
        p = 32'(value(16'(a8), 8, a_signed) * value(16'(b8), 8, b_signed));
        if (sum16 !== p[15:0] || sum32 !== p)
            $fatal(1, "MulRows W 8: %h * %h (signed %b %b): sum %h %h, expected %h",
                   a8, b8, a_signed, b_signed, sum16, sum32, p);
    endtask

    task automatic check16;
        logic [31:0] sum32;
        logic [31:0] p;
        #1;
        sum32 = '0;
        for (int r = 0; r < 19; r++)
            sum32 += rows_16_32[r];
        p = 32'(value(a16, 16, a_signed) * value(b16, 16, b_signed));
        if (sum32 !== p)
            $fatal(1, "MulRows W 16: %h * %h (signed %b %b): sum %h, expected %h",
                   a16, b16, a_signed, b_signed, sum32, p);
    endtask

    initial begin
        logic [15:0] edges [5];
        a16 = '0;
        b16 = '0;
        for (int m = 0; m < 4; m++)
            for (int x = 0; x < 256; x++)
                for (int y = 0; y < 256; y++) begin
                    {a_signed, b_signed} = 2'(m);
                    a8 = 8'(x);
                    b8 = 8'(y);
                    check8();
                end
        edges = '{16'h0000, 16'h0001, 16'h7fff, 16'h8000, 16'hffff};
        for (int m = 0; m < 4; m++)
            for (int i = 0; i < 5; i++)
                for (int k = 0; k < 5; k++) begin
                    {a_signed, b_signed} = 2'(m);
                    a16 = edges[i];
                    b16 = edges[k];
                    check16();
                end
        for (int n = 0; n < RANDOM_CASES; n++) begin
            a16      = 16'($urandom());
            b16      = 16'($urandom());
            a_signed = 1'($urandom() % 2);
            b_signed = 1'($urandom() % 2);
            check16();
        end
        $display("PASS");
        $finish;
    end
endmodule

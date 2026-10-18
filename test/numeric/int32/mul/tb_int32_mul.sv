/* Test of Int32Mul, behave or struct version.
 *
 * Every combination of a_signed and b_signed with edge values (0, 1, -1, -2^31,
 * 2^31-1, ...) and random operands. The model multiplies the 33-bit sign- or
 * zero-extended operands with SV signed arithmetic and keeps the lower 64 bits.
 * On Verilator every pair of edge values and 5000 random per combination; on Icarus
 * each edge value times the next one and 1 random (operands differ: a square can not
 * tell a from b): the struct version contains CsaMultiplier, about 1000 gates, slow
 * on event-driven Icarus.
 * Stops at the first mismatch with $fatal.
 */
module TbInt32Mul;
`ifdef VERILATOR
    localparam ALL_EDGE_PAIRS = 1;
    localparam RANDOM         = 5000;
`else
    localparam ALL_EDGE_PAIRS = 0;
    localparam RANDOM         = 1;
`endif

    reg  [31:0] a;
    reg  [31:0] b;
    reg         a_signed;
    reg         b_signed;
    wire [63:0] product;
    reg  [31:0] edges [7];
    integer     i;
    integer     j;
    integer     s;
    integer     seed;

    Int32Mul u_int32_mul(.a, .b, .a_signed, .b_signed, .product);

    // Expected product: lower 64 bits of the exact product of the extended operands.
    function automatic [63:0] model(input [31:0] x, input [31:0] y, input xs, input ys);
        logic signed [32:0] sx;
        logic signed [32:0] sy;
        // The upper 2 bits only repeat the sign of the 64-bit result.
        /* verilator lint_off UNUSEDSIGNAL */
        logic signed [65:0] full;
        /* verilator lint_on UNUSEDSIGNAL */
        sx   = {xs & x[31], x};
        sy   = {ys & y[31], y};
        full = sx * sy;
        return full[63:0];
    endfunction

    task automatic check(input [31:0] x, input [31:0] y, input xs, input ys);
        logic [63:0] exp;
        a = x;
        b = y;
        a_signed = xs;
        b_signed = ys;
        #1;
        exp = model(x, y, xs, ys);
        if (product !== exp)
            $fatal(1, "Int32Mul: %h (signed %b) * %h (signed %b) gave %h, expected %h",
                   x, xs, y, ys, product, exp);
    endtask

    initial begin
        edges[0] = 32'h0000_0000; edges[1] = 32'h0000_0001; edges[2] = 32'hffff_ffff;
        edges[3] = 32'h8000_0000; edges[4] = 32'h7fff_ffff; edges[5] = 32'h0000_0002;
        edges[6] = 32'hfffe_0001;
        seed = 1;
        for (s = 0; s < 4; s = s + 1) begin
            for (i = 0; i < 7; i = i + 1)
                for (j = 0; j < 7; j = j + 1)
                    if (ALL_EDGE_PAIRS || j == (i + 1) % 7)
                        check(edges[i], edges[j], s[1], s[0]);
            for (i = 0; i < RANDOM; i = i + 1)
                check($random(seed), $random(seed), s[1], s[0]);
        end
        $display("PASS");
        $finish;
    end
endmodule

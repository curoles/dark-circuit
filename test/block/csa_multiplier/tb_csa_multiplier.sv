/* Test of CsaMultiplier block, behave or struct version.
 *
 * WIDTH=1 and WIDTH=4: exhaustive over a and b. WIDTH=32: edge values (0, 1, all
 * ones, top bit, alternating bits), then random a and b. On Verilator every pair of
 * edge values and 5000 random; on Icarus each edge value squared and 2 random: the
 * struct version is about 1000 gates, event-driven Icarus needs ~50 ms per product.
 * The expected product is a * b computed in 2*WIDTH bits.
 * Stops at the first mismatch with $fatal.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module TbCsaMultiplier;
`ifdef VERILATOR
    localparam ALL_EDGE_PAIRS = 1;
    localparam RANDOM         = 5000;
`else
    localparam ALL_EDGE_PAIRS = 0;
    localparam RANDOM         = 2;
`endif

    reg  [0:0]  a1;
    reg  [0:0]  b1;
    wire [1:0]  p1;
    reg  [3:0]  a4;
    reg  [3:0]  b4;
    wire [7:0]  p4;
    reg  [31:0] a32;
    reg  [31:0] b32;
    wire [63:0] p32;
    reg  [31:0] edges [6];
    integer     i;
    integer     j;
    integer     seed;

    CsaMultiplier #(.WIDTH(1))  u_csa_multiplier_1 (.a(a1),  .b(b1),  .product(p1));
    CsaMultiplier #(.WIDTH(4))  u_csa_multiplier_4 (.a(a4),  .b(b4),  .product(p4));
    CsaMultiplier #(.WIDTH(32)) u_csa_multiplier_32(.a(a32), .b(b32), .product(p32));

    task automatic check32(input [31:0] x, input [31:0] y);
        logic [63:0] exp;
        a32 = x;
        b32 = y;
        #1;
        exp = {32'b0, x} * {32'b0, y};
        if (p32 !== exp)
            $fatal(1, "CsaMultiplier 32: %h * %h gave %h, expected %h", x, y, p32, exp);
    endtask

    initial begin
        for (i = 0; i < 2; i = i + 1)
            for (j = 0; j < 2; j = j + 1) begin
                a1 = i[0:0];
                b1 = j[0:0];
                #1;
                if (p1 !== {1'b0, a1} * {1'b0, b1})
                    $fatal(1, "CsaMultiplier 1: %b * %b gave %b", a1, b1, p1);
            end

        for (i = 0; i < 16; i = i + 1)
            for (j = 0; j < 16; j = j + 1) begin
                a4 = i[3:0];
                b4 = j[3:0];
                #1;
                if (p4 !== {4'b0, a4} * {4'b0, b4})
                    $fatal(1, "CsaMultiplier 4: %0d * %0d gave %0d", a4, b4, p4);
            end

        edges[0] = 32'h0000_0000; edges[1] = 32'h0000_0001; edges[2] = 32'hffff_ffff;
        edges[3] = 32'h8000_0000; edges[4] = 32'haaaa_aaaa; edges[5] = 32'h5555_5555;
        for (i = 0; i < 6; i = i + 1)
            for (j = 0; j < 6; j = j + 1)
                if (ALL_EDGE_PAIRS || i == j)
                    check32(edges[i], edges[j]);

        seed = 1;
        for (i = 0; i < RANDOM; i = i + 1)
            check32($random(seed), $random(seed));

        $display("PASS");
        $finish;
    end
endmodule

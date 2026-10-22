/* Test of WallaceMultiplier block, behave or struct version.
 *
 * WIDTH 1, 4 and 5: exhaustive over a and b (5 has rows left over in its layers).
 * WIDTH 32: edge values (0, 1, all ones, top bit, alternating bits), then random a and
 * b; on Verilator every pair of edge values and 5000 random, on Icarus each edge value
 * squared and 2 random: event-driven Icarus is slow on the gate-level version. The
 * expected product is a * b in 2*WIDTH bits. Stops at the first mismatch with $fatal.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module TbWallaceMultiplier;
`ifdef VERILATOR
    localparam bit ALL_EDGE_PAIRS = 1'b1;
    localparam int RANDOM_PAIRS   = 5000;
`else
    localparam bit ALL_EDGE_PAIRS = 1'b0;
    localparam int RANDOM_PAIRS   = 2;
`endif

    logic [0:0]  a1;
    logic [0:0]  b1;
    logic [1:0]  p1;
    logic [3:0]  a4;
    logic [3:0]  b4;
    logic [7:0]  p4;
    logic [4:0]  a5;
    logic [4:0]  b5;
    logic [9:0]  p5;
    logic [31:0] a32;
    logic [31:0] b32;
    logic [63:0] p32;
    logic [31:0] edges [6];

    WallaceMultiplier #(.WIDTH(1))  u_wallace_multiplier_1 (.a(a1),  .b(b1),  .product(p1));
    WallaceMultiplier #(.WIDTH(4))  u_wallace_multiplier_4 (.a(a4),  .b(b4),  .product(p4));
    WallaceMultiplier #(.WIDTH(5))  u_wallace_multiplier_5 (.a(a5),  .b(b5),  .product(p5));
    WallaceMultiplier #(.WIDTH(32)) u_wallace_multiplier_32(.a(a32), .b(b32), .product(p32));

    task automatic check32(logic [31:0] x, logic [31:0] y);
        logic [63:0] e;
        a32 = x;
        b32 = y;
        #1;
        e = {32'b0, x} * {32'b0, y};
        if (p32 !== e)
            $fatal(1, "WallaceMultiplier 32: %h * %h gave %h, expected %h", x, y, p32, e);
    endtask

    initial begin
        for (int i = 0; i < 2; i++)
            for (int j = 0; j < 2; j++) begin
                a1 = i[0:0];
                b1 = j[0:0];
                #1;
                if (p1 !== {1'b0, a1} * {1'b0, b1})
                    $fatal(1, "WallaceMultiplier 1: %b * %b gave %b", a1, b1, p1);
            end

        for (int i = 0; i < 16; i++)
            for (int j = 0; j < 16; j++) begin
                a4 = i[3:0];
                b4 = j[3:0];
                #1;
                if (p4 !== {4'b0, a4} * {4'b0, b4})
                    $fatal(1, "WallaceMultiplier 4: %0d * %0d gave %0d", a4, b4, p4);
            end

        for (int i = 0; i < 32; i++)
            for (int j = 0; j < 32; j++) begin
                a5 = i[4:0];
                b5 = j[4:0];
                #1;
                if (p5 !== {5'b0, a5} * {5'b0, b5})
                    $fatal(1, "WallaceMultiplier 5: %0d * %0d gave %0d", a5, b5, p5);
            end

        edges[0] = 32'h0000_0000;
        edges[1] = 32'h0000_0001;
        edges[2] = 32'hffff_ffff;
        edges[3] = 32'h8000_0000;
        edges[4] = 32'haaaa_aaaa;
        edges[5] = 32'h5555_5555;
        for (int i = 0; i < 6; i++)
            for (int j = 0; j < 6; j++)
                if (ALL_EDGE_PAIRS || i == j)
                    check32(edges[i], edges[j]);

        for (int i = 0; i < RANDOM_PAIRS; i++)
            check32($urandom, $urandom);

        $finish;
    end

endmodule

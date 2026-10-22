/* Test of WallaceTree block, behave or struct version.
 *
 * Checks sum + carry against the sum of the rows, mod 2^WIDTH: the two versions split
 * the total differently between sum and carry. Exhaustive: 3 rows of 4 bits, 4 rows of
 * 3 bits. 64 bits: 1, 2, 5 and 35 rows (35: Int32Mul), the same values in their first
 * rows; zeros, all ones (the most carries), then random rows: 5000 sets on Verilator, 20
 * on Icarus (event-driven Icarus is slow on the gate-level tree). Stops at the first
 * mismatch with $fatal.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module TbWallaceTree;
`ifdef VERILATOR
    localparam int RANDOM_SETS = 5000;
`else
    localparam int RANDOM_SETS = 20;
`endif

    logic [3:0]  r3x4 [3];
    logic [3:0]  s3x4;
    logic [3:0]  c3x4;
    logic [2:0]  r4x3 [4];
    logic [2:0]  s4x3;
    logic [2:0]  c4x3;
    logic [63:0] r1 [1];
    logic [63:0] s1;
    logic [63:0] c1;
    logic [63:0] r2 [2];
    logic [63:0] s2;
    logic [63:0] c2;
    logic [63:0] r5 [5];
    logic [63:0] s5;
    logic [63:0] c5;
    logic [63:0] r35 [35];
    logic [63:0] s35;
    logic [63:0] c35;

    WallaceTree #(.ROWS(3),  .WIDTH(4))  u_wallace_tree_3x4(.rows(r3x4), .sum(s3x4), .carry(c3x4));
    WallaceTree #(.ROWS(4),  .WIDTH(3))  u_wallace_tree_4x3(.rows(r4x3), .sum(s4x3), .carry(c4x3));
    WallaceTree #(.ROWS(1),  .WIDTH(64)) u_wallace_tree_1  (.rows(r1),   .sum(s1),   .carry(c1));
    WallaceTree #(.ROWS(2),  .WIDTH(64)) u_wallace_tree_2  (.rows(r2),   .sum(s2),   .carry(c2));
    WallaceTree #(.ROWS(5),  .WIDTH(64)) u_wallace_tree_5  (.rows(r5),   .sum(s5),   .carry(c5));
    WallaceTree #(.ROWS(35), .WIDTH(64)) u_wallace_tree_35 (.rows(r35),  .sum(s35),  .carry(c35));

    // The 64-bit trees: the first 1, 2, 5 rows of r35 into the smaller ones, then every
    // tree against the sum of its rows.
    task automatic check64();
        logic [63:0] t;
        r1[0] = r35[0];
        for (int i = 0; i < 2; i++)
            r2[i] = r35[i];
        for (int i = 0; i < 5; i++)
            r5[i] = r35[i];
        #1;
        t = '0;
        for (int i = 0; i < 35; i++) begin
            t = t + r35[i];
            if (i == 0 && s1 + c1 !== t)
                $fatal(1, "1 row: sum %h + carry %h, expected %h", s1, c1, t);
            if (i == 1 && s2 + c2 !== t)
                $fatal(1, "2 rows: sum %h + carry %h, expected %h", s2, c2, t);
            if (i == 4 && s5 + c5 !== t)
                $fatal(1, "5 rows: sum %h + carry %h, expected %h", s5, c5, t);
        end
        if (s35 + c35 !== t)
            $fatal(1, "35 rows: sum %h + carry %h, expected %h", s35, c35, t);
    endtask

    initial begin
        for (int i = 0; i < 2**12; i++) begin
            r3x4[0] = i[3:0];
            r3x4[1] = i[7:4];
            r3x4[2] = i[11:8];
            r4x3[0] = i[2:0];
            r4x3[1] = i[5:3];
            r4x3[2] = i[8:6];
            r4x3[3] = i[11:9];
            #1;
            if (s3x4 + c3x4 !== r3x4[0] + r3x4[1] + r3x4[2])
                $fatal(1, "3x4: %h %h %h: sum %h carry %h", r3x4[0], r3x4[1], r3x4[2], s3x4, c3x4);
            if (s4x3 + c4x3 !== r4x3[0] + r4x3[1] + r4x3[2] + r4x3[3])
                $fatal(1, "4x3: %h %h %h %h: sum %h carry %h",
                       r4x3[0], r4x3[1], r4x3[2], r4x3[3], s4x3, c4x3);
        end

        for (int i = 0; i < 35; i++)
            r35[i] = '0;
        check64();
        for (int i = 0; i < 35; i++)
            r35[i] = '1;
        check64();
        for (int n = 0; n < RANDOM_SETS; n++) begin
            for (int i = 0; i < 35; i++)
                r35[i] = {$urandom, $urandom};
            check64();
        end

        $finish;
    end

endmodule

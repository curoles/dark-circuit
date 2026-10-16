/* Test of AddCmp block, behave or struct version.
 *
 * WIDTH=4 and WIDTH=1: exhaustive over a, b and c, so eq=0 is checked as much as eq=1.
 * WIDTH=50: random a and b, and c of three kinds: a + b (eq=1, also when the sum
 * wraps around), near miss of a + b with one bit flipped or +-1 (eq=0),
 * and random (almost always eq=0).
 * Stops at the first mismatch with $fatal.
 */
module TbAddCmp;
    localparam W = 50;

    reg  [3:0]   a4;
    reg  [3:0]   b4;
    reg  [3:0]   c4;
    reg  [3:0]   sum4;
    wire         eq4;
    reg          a1;
    reg          b1;
    reg          c1;
    wire         eq1;
    reg  [W-1:0] a50;
    reg  [W-1:0] b50;
    reg  [W-1:0] c50;
    reg  [W-1:0] sum50;
    wire         eq50;
    // Random words, only some of their bits are used.
    /* verilator lint_off UNUSEDSIGNAL */
    reg  [63:0]  ra;
    reg  [63:0]  rb;
    reg  [63:0]  rc;
    reg  [31:0]  rk;
    /* verilator lint_on UNUSEDSIGNAL */
    integer i;
    integer k;
    integer seed;

    AddCmp #(.WIDTH(4)) u_add_cmp_4 (.a(a4),  .b(b4),  .c(c4),  .eq(eq4));
    AddCmp #(.WIDTH(1)) u_add_cmp_1 (.a(a1),  .b(b1),  .c(c1),  .eq(eq1));
    AddCmp #(.WIDTH(W)) u_add_cmp_50(.a(a50), .b(b50), .c(c50), .eq(eq50));

    initial begin
        a50 = 0; b50 = 0; c50 = 0;

        // WIDTH=4 and WIDTH=1, exhaustive.
        for (i = 0; i < (1 << 12); i = i + 1) begin
            {a4, b4, c4} = i[11:0];
            {a1, b1, c1} = i[2:0];
            sum4 = a4 + b4;
            #1;
            if (eq4 !== (sum4 == c4))
                $fatal(1, "AddCmp 4: a=%h b=%h c=%h got eq=%b, expected %b", a4, b4, c4, eq4, sum4 == c4);
            if (eq1 !== ((a1 ^ b1) == c1))
                $fatal(1, "AddCmp 1: a=%b b=%b c=%b got eq=%b, expected %b", a1, b1, c1, eq1, (a1 ^ b1) == c1);
        end

        // WIDTH=50, random.
        seed = 1;
        for (i = 0; i < 3000; i = i + 1) begin
            ra = {$random(seed), $random(seed)};
            rb = {$random(seed), $random(seed)};
            rc = {$random(seed), $random(seed)};
            rk = $random(seed);
            a50 = ra[W-1:0];
            b50 = rb[W-1:0];
            sum50 = a50 + b50;
            k = int'(rk[7:0]) % W;
            case (rk[9:8])
                2'd0:    c50 = sum50;                         // equal
                2'd1:    c50 = sum50 ^ ({{(W-1){1'b0}}, 1'b1} << k);  // one bit flipped
                2'd2:    c50 = rk[10] ? sum50 + 1'b1 : sum50 - 1'b1;  // +-1
                default: c50 = rc[W-1:0];                     // random
            endcase
            #1;
            if (eq50 !== (sum50 == c50))
                $fatal(1, "AddCmp 50: a=%h b=%h c=%h got eq=%b, expected %b", a50, b50, c50, eq50, sum50 == c50);
        end

        $display("PASS");
        $finish;
    end
endmodule

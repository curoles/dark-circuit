/* Test of LimDff, Logic-in-Memory DFF.
 *
 * 1. Documented operations, each checked against its named meaning.
 * 2. Random operations checked against reference model of the priority logic.
 *
 * Inputs change while clk is 0, value is stored on rising edge.
 * Stops at the first mismatch with $fatal.
 */
module TbLimDff;
    localparam W = 4;

    reg          clk;
    reg          do_force;
    reg          do_invert;
    reg          do_nand;
    reg          do_xnor;
    reg  [W-1:0] in;
    wire [W-1:0] out;

    reg  [W-1:0] cur;
    reg  [W-1:0] b4inv;
    reg  [W-1:0] exp;
    // Random word, only some of its bits are used.
    /* verilator lint_off UNUSEDSIGNAL */
    reg  [31:0]  r;
    /* verilator lint_on UNUSEDSIGNAL */
    integer i;
    integer seed;

    LimDff #(.WIDTH(W)) u_lim_dff(.clk(clk), .do_force(do_force), .do_invert(do_invert),
                                  .do_nand(do_nand), .do_xnor(do_xnor), .in(in), .out(out));

    // One clock cycle: set inputs while clk is 0, store on rising edge, check stored value.
    task op(input integer step, input f, input inv, input nd, input xn,
            input [W-1:0] value, input [W-1:0] expected);
        begin
            do_force = f; do_invert = inv; do_nand = nd; do_xnor = xn; in = value;
            #5 clk = 1;
            #1;
            if (out !== expected)
                $fatal(1, "LimDff step %0d: force=%b invert=%b nand=%b xnor=%b in=%b got=%b, expected %b",
                       step, f, inv, nd, xn, value, out, expected);
            #4 clk = 0;
        end
    endtask

    // Current 1100 and new 1010 give all 4 bit combinations.
    localparam [W-1:0] CUR = 4'b1100;
    localparam [W-1:0] NEW = 4'b1010;

    initial begin
        clk = 0; do_force = 0; do_invert = 0; do_nand = 0; do_xnor = 0; in = 0;

        // 1. Set new value, also inverted.
        op(1, 1, 0, 0, 0, NEW,  NEW);
        op(2, 1, 1, 0, 0, ~CUR, CUR);
        // 2. Do not change current value.
        op(3, 0, 1, 0, 0, 0,    CUR);
        // 3. NAND(current,new).
        op(4, 1, 0, 0, 0, CUR,  CUR);
        op(5, 0, 0, 1, 0, NEW,  ~(CUR & NEW));
        // 4. AND(current,new).
        op(6, 1, 0, 0, 0, CUR,  CUR);
        op(7, 0, 1, 1, 0, NEW,  CUR & NEW);
        // 5. XNOR(current,new).
        op(8, 1, 0, 0, 0, CUR,  CUR);
        op(9, 0, 0, 0, 1, NEW,  ~(CUR ^ NEW));
        // 6. XOR(current,new).
        op(10, 1, 0, 0, 0, CUR, CUR);
        op(11, 0, 1, 0, 1, NEW, CUR ^ NEW);
        // 7. NOR(current,new).
        op(12, 1, 0, 0, 0, CUR, CUR);
        op(13, 0, 0, 0, 0, NEW, ~(CUR | NEW));
        // 8. OR(current,new).
        op(14, 1, 0, 0, 0, CUR, CUR);
        op(15, 0, 1, 0, 0, NEW, CUR | NEW);

        // Random operations: priority do_force, do_nand, do_xnor, otherwise NOR; then do_invert.
        cur = CUR | NEW;
        seed = 1;
        for (i = 0; i < 1000; i = i + 1) begin
            r = $random(seed);
            if (r[0])      b4inv = r[W+7:8];
            else if (r[2]) b4inv = ~(r[W+7:8] & cur);
            else if (r[3]) b4inv = ~(r[W+7:8] ^ cur);
            else           b4inv = ~(r[W+7:8] | cur);
            exp = r[1] ? ~b4inv : b4inv;
            op(100 + i, r[0], r[1], r[2], r[3], r[W+7:8], exp);
            cur = exp;
        end

        $display("PASS");
        $finish;
    end
endmodule

/* Test of Int32Div, behave or struct version.
 *
 * Signed and unsigned mode with edge values (0, 1, -1, 2, -2^31, 2^31-1, alternating
 * bits) and random operands: on Verilator every pair of edge values and many random,
 * on Icarus each edge value with the next one and a few random. Expected: SV / and %
 * on $signed operands (rounding toward zero, remainder with the sign of the dividend)
 * or on unsigned ones. div_by_zero must be 1 exactly for divisor 0, overflow exactly
 * for signed -2^31 / -1; then only the flags are compared (the values are undefined).
 * Every division also checks the handshake: busy for exactly 32 clocks (with
 * EARLY_START, the significant bits of the dividend's magnitude, at least 1; 32 for
 * divisor 0), done in the last, results and flags that stay after done, and a start while
 * busy (with other operands) that is ignored. Runs both EARLY_START settings.
 * Stops at the first mismatch with $fatal.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module TbInt32DivCheck #(
    parameter EARLY_START = 0
)(
    input  wire clk,
    input  wire rst_n,
    output reg  finished
);
`ifdef VERILATOR
    localparam ALL_EDGE_PAIRS = 1;
    localparam RANDOM         = 2000;
`else
    localparam ALL_EDGE_PAIRS = 0;
    localparam RANDOM         = 5;      // two checks run: keep the struct test near 1 s
`endif

    reg  [31:0] dividend;
    reg  [31:0] divisor;
    reg         signed_op;
    reg         start;
    wire        busy;
    wire        done;
    wire [31:0] quotient;
    wire [31:0] remainder;
    wire        div_by_zero;
    wire        overflow;
    reg  [31:0] edges [7];
    reg  [31:0] ry;
    integer     i;
    integer     j;
    integer     s;
    integer     seed;

    Int32Div #(.EARLY_START(EARLY_START)) u_int32_div(
        .clk, .rst_n, .start, .dividend, .divisor, .signed_op, .busy, .done, .quotient,
        .remainder, .div_by_zero, .overflow);

    // Clocks of a division: 32, or with EARLY_START the significant bits of the magnitude of
    // x (at least 1), unless y is 0.
    function automatic integer clocks_of(input [31:0] x, input [31:0] y, input sop);
        logic [31:0] m;
        integer      n;
        if (EARLY_START == 0 || y == 0)
            return 32;
        m = (sop && x[31]) ? -x : x;
        n = 1;
        for (int k = 0; k < 32; k++)
            if (m[k])
                n = k + 1;
        return n;
    endfunction

    // Divide x by y; in the middle of the division start again with other operands,
    // which must be ignored.
    task automatic divide(input [31:0] x, input [31:0] y, input sop);
        logic [31:0] exp_q;
        logic [31:0] exp_r;
        logic        exp_zero;
        logic        exp_ovf;
        integer      clocks;
        integer      exp_clocks;
        exp_zero = y == 0;
        exp_ovf  = sop && x == 32'h8000_0000 && y == 32'hffff_ffff;
        exp_clocks = clocks_of(x, y, sop);
        exp_q    = 0;
        exp_r    = 0;
        if (!exp_zero && !exp_ovf) begin
            if (sop) begin
                exp_q = $signed(x) / $signed(y);
                exp_r = $signed(x) % $signed(y);
            end else begin
                exp_q = x / y;
                exp_r = x % y;
            end
        end
        @(negedge clk);
        if (busy)
            $fatal(1, "Int32Div: busy before start");
        dividend  = x;
        divisor   = y;
        signed_op = sop;
        start     = 1;
        @(negedge clk);
        start     = 0;
        clocks    = 0;
        while (busy) begin
            clocks = clocks + 1;
            if (clocks == (exp_clocks + 1) / 2) begin
                dividend  = ~x;
                divisor   = (y == 0) ? 32'd3 : 32'd0;
                signed_op = !sop;
                start     = 1;
            end else
                start     = 0;
            if (done !== (clocks == exp_clocks))
                $fatal(1, "Int32Div: done=%b in busy clock %0d", done, clocks);
            @(negedge clk);
        end
        start = 0;
        if (clocks != exp_clocks)
            $fatal(1, "Int32Div: %h / %h (signed %b) busy for %0d clocks, expected %0d", x, y,
                   sop, clocks, exp_clocks);
        repeat (2) begin
            if (div_by_zero !== exp_zero || overflow !== exp_ovf)
                $fatal(1, "Int32Div: %h / %h (signed %b): div_by_zero=%b overflow=%b, expected %b %b",
                       x, y, sop, div_by_zero, overflow, exp_zero, exp_ovf);
            if (!exp_zero && !exp_ovf && (quotient !== exp_q || remainder !== exp_r))
                $fatal(1, "Int32Div: %h / %h (signed %b) gave %h rem %h, expected %h rem %h",
                       x, y, sop, quotient, remainder, exp_q, exp_r);
            @(negedge clk);     // results stay after done
        end
    endtask

    initial begin
        finished  = 0;
        start     = 0;
        dividend  = 0;
        divisor   = 0;
        signed_op = 0;
        edges[0] = 32'h0000_0000; edges[1] = 32'h0000_0001; edges[2] = 32'hffff_ffff;
        edges[3] = 32'h8000_0000; edges[4] = 32'h7fff_ffff; edges[5] = 32'h0000_0002;
        edges[6] = 32'haaaa_aaaa;
        @(posedge rst_n);
        seed = 1;
        for (s = 0; s < 2; s = s + 1) begin
            for (i = 0; i < 7; i = i + 1)
                for (j = 0; j < 7; j = j + 1)
                    if (ALL_EDGE_PAIRS || j == (i + 1) % 7)
                        divide(edges[i], edges[j], s[0]);
            divide(32'h8000_0000, 32'hffff_ffff, s[0]);   // overflow in signed mode
            for (i = 0; i < RANDOM; i = i + 1) begin
                ry = $random(seed);
                divide($random(seed), (i % 4 == 0) ? ry >> (i % 32) : ry, s[0]);
            end
        end
        finished = 1;
    end
endmodule

module TbInt32Div;
    wire clk;
    wire rst_n;
    wire finished;
    wire finished_early;

    SimClkGen #(.HALF_PERIOD(5)) u_sim_clk_gen(.clk);
    SimRstGen #(.CYCLES(2))      u_sim_rst_gen(.clk, .rst_n);

    TbInt32DivCheck #(.EARLY_START(0)) u_check(.clk, .rst_n, .finished);
    TbInt32DivCheck #(.EARLY_START(1)) u_check_early(.clk, .rst_n, .finished(finished_early));

    initial begin
        wait (finished && finished_early);
        $display("PASS");
        $finish;
    end
endmodule

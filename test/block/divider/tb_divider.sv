/* Test of Divider block, behave or struct version.
 *
 * WIDTH=4: every dividend and divisor, divisor 0 too. WIDTH=32: edge values (0, 1,
 * all ones, top bit, top bit clear, 2, alternating bits) and random operands; on
 * Verilator every pair of edge values and many random, on Icarus each edge value with
 * the next one (operands differ) and a few random. Expected: x / y and x % y, and for
 * y = 0 quotient all ones and remainder x. Every division also checks the handshake:
 * busy for exactly WIDTH clocks, done in the last of them, results that stay after
 * done, and a start while busy that is ignored (the first division wins).
 * Stops at the first mismatch with $fatal.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module TbDividerWidth #(
    parameter WIDTH  = 4,
    parameter RANDOM = 0
)(
    input  wire clk,
    input  wire rst_n,
    output reg  finished
);
`ifdef VERILATOR
    localparam ALL_EDGE_PAIRS = 1;
`else
    localparam ALL_EDGE_PAIRS = 0;
`endif

    reg  [WIDTH-1:0] dividend;
    reg  [WIDTH-1:0] divisor;
    reg              start;
    wire             busy;
    wire             done;
    wire [WIDTH-1:0] quotient;
    wire [WIDTH-1:0] remainder;
    reg  [WIDTH-1:0] edges [7];
    // Random words, only WIDTH bits are used.
    /* verilator lint_off UNUSEDSIGNAL */
    reg  [31:0]      rx;
    reg  [31:0]      ry;
    /* verilator lint_on UNUSEDSIGNAL */
    integer          i;
    integer          j;
    integer          seed;

    Divider #(.WIDTH(WIDTH)) u_divider(.clk, .rst_n, .start, .dividend, .divisor, .busy, .done,
                                       .quotient, .remainder);

    // Divide x by y; in the middle of the division start again with other operands,
    // which must be ignored.
    task automatic divide(input [WIDTH-1:0] x, input [WIDTH-1:0] y);
        logic [WIDTH-1:0] exp_q;
        logic [WIDTH-1:0] exp_r;
        integer           clocks;
        exp_q = (y == 0) ? {WIDTH{1'b1}} : x / y;
        exp_r = (y == 0) ? x : x % y;
        @(negedge clk);
        if (busy)
            $fatal(1, "Divider %0d: busy before start", WIDTH);
        dividend = x;
        divisor  = y;
        start    = 1;
        @(negedge clk);
        start    = 0;
        clocks   = 0;
        while (busy) begin
            clocks = clocks + 1;
            if (clocks == WIDTH / 2) begin
                dividend = ~x;
                divisor  = ~y;
                start    = 1;
            end else
                start    = 0;
            if (done !== (clocks == WIDTH))
                $fatal(1, "Divider %0d: done=%b in busy clock %0d", WIDTH, done, clocks);
            @(negedge clk);
        end
        start = 0;
        if (clocks != WIDTH)
            $fatal(1, "Divider %0d: busy for %0d clocks, expected %0d", WIDTH, clocks, WIDTH);
        repeat (2) begin
            if (quotient !== exp_q || remainder !== exp_r)
                $fatal(1, "Divider %0d: %h / %h gave %h rem %h, expected %h rem %h",
                       WIDTH, x, y, quotient, remainder, exp_q, exp_r);
            @(negedge clk);     // results stay after done
        end
    endtask

    initial begin
        finished = 0;
        start    = 0;
        dividend = '0;
        divisor  = '0;
        @(posedge rst_n);
        if (WIDTH <= 4) begin
            for (i = 0; i < (1 << WIDTH); i = i + 1)
                for (j = 0; j < (1 << WIDTH); j = j + 1)
                    divide(i[WIDTH-1:0], j[WIDTH-1:0]);
        end else begin
            edges[0] = '0;
            edges[1] = 1;
            edges[2] = '1;
            edges[3] = {1'b1, {(WIDTH-1){1'b0}}};
            edges[4] = {1'b0, {(WIDTH-1){1'b1}}};
            edges[5] = 2;
            edges[6] = {(WIDTH/2){2'b10}};
            for (i = 0; i < 7; i = i + 1)
                for (j = 0; j < 7; j = j + 1)
                    if (ALL_EDGE_PAIRS || j == (i + 1) % 7)
                        divide(edges[i], edges[j]);
            seed = 1;
            for (i = 0; i < RANDOM; i = i + 1) begin
                rx = $random(seed);
                ry = $random(seed);
                divide(rx[WIDTH-1:0], (i % 4 == 0) ? ry[WIDTH-1:0] >> (i % WIDTH) : ry[WIDTH-1:0]);
            end
        end
        finished = 1;
    end
endmodule

module TbDivider;
`ifdef VERILATOR
    localparam RANDOM = 2000;
`else
    localparam RANDOM = 20;
`endif

    wire clk;
    wire rst_n;
    wire finished4;
    wire finished32;

    SimClkGen #(.HALF_PERIOD(5)) u_sim_clk_gen(.clk);
    SimRstGen #(.CYCLES(2))      u_sim_rst_gen(.clk, .rst_n);

    TbDividerWidth #(.WIDTH(4))                    u_tb_divider_4 (.clk, .rst_n, .finished(finished4));
    TbDividerWidth #(.WIDTH(32), .RANDOM(RANDOM))  u_tb_divider_32(.clk, .rst_n, .finished(finished32));

    initial begin
        wait (finished4 && finished32);
        $display("PASS");
        $finish;
    end
endmodule

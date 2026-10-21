/* Test of Fifo block, behave or struct version.
 *
 * Three instances with the same inputs, every one has its own model:
 *   0: ADDR_WIDTH=2 (4 entries), default thresholds
 *   1: ADDR_WIDTH=3 (8 entries), ALMOST_FULL=5, ALMOST_EMPTY=2
 *   2: ADDR_WIDTH=1 (2 entries), default thresholds
 * Model is array with head index and count. Inputs change on falling edge,
 * after every rising edge data_out (when not empty), empty, full, count,
 * almost_full and almost_empty of every instance are compared with its model.
 * Stops at the first mismatch with $fatal.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module TbFifo;
    localparam DW = 8;

    wire          clk;
    reg           rst_n;
    reg           write;
    reg           read;
    reg  [DW-1:0] data_in;

    wire [DW-1:0] data_out0;
    wire          empty0;
    wire          full0;
    wire [2:0]    count0;
    wire          almost_full0;
    wire          almost_empty0;
    wire [DW-1:0] data_out1;
    wire          empty1;
    wire          full1;
    wire [3:0]    count1;
    wire          almost_full1;
    wire          almost_empty1;
    wire [DW-1:0] data_out2;
    wire          empty2;
    wire          full2;
    wire [1:0]    count2;
    wire          almost_full2;
    wire          almost_empty2;

    // Models: entries, index of the oldest entry, number of entries.
    reg  [DW-1:0] model [3][8];
    integer       head [3];
    integer       cnt [3];
    integer       depth [3];
    integer       almost_full_level [3];
    integer       almost_empty_level [3];
    integer       k;
    // Random word, only some of its bits are used.
    /* verilator lint_off UNUSEDSIGNAL */
    reg  [31:0]   r;
    /* verilator lint_on UNUSEDSIGNAL */
    integer i;
    integer seed;

    SimClkGen #(.HALF_PERIOD(5)) u_sim_clk_gen(.clk(clk));

    Fifo #(.ADDR_WIDTH(2), .DATA_WIDTH(DW)) u_fifo_0(
        .clk(clk), .rst_n(rst_n), .write(write), .data_in(data_in), .read(read),
        .data_out(data_out0), .empty(empty0), .full(full0), .count(count0),
        .almost_full(almost_full0), .almost_empty(almost_empty0));
    Fifo #(.ADDR_WIDTH(3), .DATA_WIDTH(DW), .ALMOST_FULL(5), .ALMOST_EMPTY(2)) u_fifo_1(
        .clk(clk), .rst_n(rst_n), .write(write), .data_in(data_in), .read(read),
        .data_out(data_out1), .empty(empty1), .full(full1), .count(count1),
        .almost_full(almost_full1), .almost_empty(almost_empty1));
    Fifo #(.ADDR_WIDTH(1), .DATA_WIDTH(DW)) u_fifo_2(
        .clk(clk), .rst_n(rst_n), .write(write), .data_in(data_in), .read(read),
        .data_out(data_out2), .empty(empty2), .full(full2), .count(count2),
        .almost_full(almost_full2), .almost_empty(almost_empty2));

    // Compare outputs of instance n with its model.
    task check(input integer step, input integer n, input [DW-1:0] dout, input e, input f,
               input [3:0] c, input af, input ae);
        begin
            if ((cnt[n] > 0 && dout !== model[n][head[n]]) ||
                e !== (cnt[n] == 0) || f !== (cnt[n] == depth[n]) || c !== cnt[n][3:0] ||
                af !== (cnt[n] >= almost_full_level[n]) || ae !== (cnt[n] <= almost_empty_level[n]))
                $fatal(1, "Fifo %0d step %0d: rst_n=%b write=%b read=%b data_in=%h got data_out=%h empty=%b full=%b count=%0d almost_full=%b almost_empty=%b, expected data_out=%h count=%0d",
                       n, step, rst_n, write, read, data_in, dout, e, f, c, af, ae,
                       model[n][head[n]], cnt[n]);
        end
    endtask

    // One clock cycle: set inputs after falling edge, check after rising edge.
    task cycle(input integer step, input rn, input w, input rd, input [DW-1:0] d);
        integer do_write;
        integer do_read;
        begin
            @(negedge clk);
            rst_n = rn; write = w; read = rd; data_in = d;
            @(posedge clk);
            for (k = 0; k < 3; k = k + 1) begin
                if (!rn) begin
                    head[k] = 0;
                    cnt[k]  = 0;
                end else begin
                    // Write ignored when full, read ignored when empty, both by old count.
                    do_write = (w && cnt[k] < depth[k]) ? 1 : 0;
                    do_read  = (rd && cnt[k] > 0) ? 1 : 0;
                    if (do_write == 1) model[k][(head[k] + cnt[k]) % depth[k]] = d;
                    if (do_read == 1)  head[k] = (head[k] + 1) % depth[k];
                    cnt[k] = cnt[k] + do_write - do_read;
                end
            end
            #1;
            check(step, 0, data_out0, empty0, full0, {1'b0, count0},  almost_full0, almost_empty0);
            check(step, 1, data_out1, empty1, full1, count1,          almost_full1, almost_empty1);
            check(step, 2, data_out2, empty2, full2, {2'b0, count2},  almost_full2, almost_empty2);
        end
    endtask

    initial begin
        depth[0] = 4; almost_full_level[0] = 3; almost_empty_level[0] = 1;
        depth[1] = 8; almost_full_level[1] = 5; almost_empty_level[1] = 2;
        depth[2] = 2; almost_full_level[2] = 1; almost_empty_level[2] = 1;
        rst_n = 0; write = 0; read = 0; data_in = 0;

        // 1. Reset.
        cycle(0, 0, 0, 0, 8'h00);
        cycle(1, 0, 1, 1, 8'h00);
        // 2. Fill past full: writes when full are ignored.
        for (i = 0; i < 10; i = i + 1)
            cycle(100 + i, 1, 1, 0, 8'h10 + i[7:0]);
        // 3. Drain past empty: reads when empty are ignored.
        for (i = 0; i < 10; i = i + 1)
            cycle(200 + i, 1, 0, 1, 8'h00);
        // 4. Read and write together: at empty the read is ignored,
        //    at full the write is ignored, in between both happen.
        cycle(300, 1, 1, 1, 8'h30);
        for (i = 0; i < 10; i = i + 1)
            cycle(310 + i, 1, 1, 0, 8'h31 + i[7:0]);
        cycle(320, 1, 1, 1, 8'h40);
        cycle(321, 1, 1, 1, 8'h41);
        cycle(322, 1, 1, 1, 8'h42);
        // 5. Reset in the middle empties the FIFO.
        cycle(400, 1, 0, 1, 8'h00);
        cycle(401, 0, 1, 1, 8'h50);
        cycle(402, 1, 1, 0, 8'h51);
        cycle(403, 1, 0, 1, 8'h00);
        // 6. Random cycles, reset is rare.
        seed = 1;
        for (i = 0; i < 2000; i = i + 1) begin
            r = $random(seed);
            cycle(1000 + i, r[11:4] != 0, r[0], r[1], r[23:16]);
        end

        $display("PASS");
        $finish;
    end
endmodule

/* Test of Sram1R1W block, behave or struct version.
 *
 * Inputs change on falling edge, after every rising edge
 * data_out is compared with model of the memory.
 * Stops at the first mismatch with $fatal.
 */
module TbSram1R1W;
    localparam AW    = 3;
    localparam DW    = 8;
    localparam WORDS = 1 << AW;

    wire          clk;
    reg           rd_en;
    reg           wr_en;
    reg  [AW-1:0] rd_addr;
    reg  [AW-1:0] wr_addr;
    reg  [DW-1:0] data_in;
    wire [DW-1:0] data_out;

    reg  [DW-1:0] model [WORDS];
    reg  [DW-1:0] exp_out;  // unknown until the first read
    reg  [DW-1:0] value;
    // Random word, only some of its bits are used.
    /* verilator lint_off UNUSEDSIGNAL */
    reg  [31:0]   r;
    integer       next_addr;
    /* verilator lint_on UNUSEDSIGNAL */
    integer i;
    integer seed;

    SimClkGen #(.HALF_PERIOD(5)) u_sim_clk_gen(.clk(clk));

    Sram1R1W #(.ADDR_WIDTH(AW), .DATA_WIDTH(DW)) u_sram_1r1w(
        .clk(clk), .rd_en(rd_en), .wr_en(wr_en), .rd_addr(rd_addr), .wr_addr(wr_addr),
        .data_in(data_in), .data_out(data_out));

    // One clock cycle: set inputs after falling edge, check after rising edge.
    task cycle(input integer step, input re, input [AW-1:0] ra, input we, input [AW-1:0] wa, input [DW-1:0] d);
        begin
            @(negedge clk);
            rd_en = re; rd_addr = ra; wr_en = we; wr_addr = wa; data_in = d;
            @(posedge clk);
            if (re) exp_out = model[ra];  // read-first: old data
            if (we) model[wa] = d;
            #1;
            if (data_out !== exp_out)
                $fatal(1, "Sram1R1W step %0d: rd_en=%b rd_addr=%0d wr_en=%b wr_addr=%0d data_in=%h got data_out=%h, expected %h",
                       step, re, ra, we, wa, d, data_out, exp_out);
        end
    endtask

    initial begin
        rd_en = 0; wr_en = 0; rd_addr = 0; wr_addr = 0; data_in = 0;

        // 1. Write every address.
        for (i = 0; i < WORDS; i = i + 1) begin
            value = i[DW-1:0] * 8'd37 + 8'd5;
            cycle(i, 0, 0, 1, i[AW-1:0], value);
        end
        // 2. Read every address back.
        for (i = 0; i < WORDS; i = i + 1)
            cycle(100 + i, 1, i[AW-1:0], 0, 0, 0);
        // 3. Read and write different addresses in the same cycle.
        for (i = 0; i < WORDS; i = i + 1) begin
            next_addr = i + 1;
            value = i[DW-1:0] * 8'd11 + 8'd200;
            cycle(200 + i, 1, i[AW-1:0], 1, next_addr[AW-1:0], value);
        end
        // 4. Read and write the same address in the same cycle reads old data.
        cycle(300, 1, 3'd2, 1, 3'd2, 8'hA5);
        cycle(301, 1, 3'd2, 0, 3'd0, 8'h00);
        // 5. rd_en=0 holds data_out, wr_en=0 does not write.
        cycle(400, 0, 3'd5, 0, 3'd0, 8'h00);
        cycle(401, 0, 3'd6, 0, 3'd0, 8'h00);
        cycle(402, 1, 3'd3, 0, 3'd3, 8'hFF);
        // 6. Random cycles, every address was written in 1.
        seed = 1;
        for (i = 0; i < 1000; i = i + 1) begin
            r = $random(seed);
            cycle(1000 + i, r[0], r[AW+3:4], r[1], r[AW+7:8], r[DW+15:16]);
        end

        $display("PASS");
        $finish;
    end
endmodule

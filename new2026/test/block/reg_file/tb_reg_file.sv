/* Test of RegFile block, behave or struct version.
 *
 * Two instances: A with 2 read ports and 1 write port, B with 1 read port and
 * 2 write ports; B reads at read port 0 address of A and writes at write port 0 of A.
 * Inputs change on falling edge. Read is combinational, so rd_data is compared
 * with model of the registers before rising edge (old values) and after it (new values).
 * Stops at the first mismatch with $fatal.
 */
module TbRegFile;
    localparam AW   = 3;
    localparam DW   = 8;
    localparam REGS = 1 << AW;

    wire               clk;
    reg  [1:0][AW-1:0] rd_addr;
    wire [1:0][DW-1:0] rd_data_a;
    wire [DW-1:0]      rd_data_b;
    reg  [1:0]         wr_en;
    reg  [1:0][AW-1:0] wr_addr;
    reg  [1:0][DW-1:0] wr_data;

    reg  [DW-1:0] model_a [REGS];
    reg  [DW-1:0] model_b [REGS];
    reg  [DW-1:0] value;
    // Random word, only some of its bits are used.
    /* verilator lint_off UNUSEDSIGNAL */
    reg  [31:0]   r;
    integer       other_addr;
    /* verilator lint_on UNUSEDSIGNAL */
    integer i;
    integer seed;

    SimClkGen #(.HALF_PERIOD(5)) u_sim_clk_gen(.clk(clk));

    RegFile #(.RD_PORTS(2), .WR_PORTS(1), .ADDR_WIDTH(AW), .DATA_WIDTH(DW)) u_reg_file_a(
        .clk(clk), .rd_addr(rd_addr), .rd_data(rd_data_a),
        .wr_en(wr_en[0]), .wr_addr(wr_addr[0]), .wr_data(wr_data[0]));

    RegFile #(.RD_PORTS(1), .WR_PORTS(2), .ADDR_WIDTH(AW), .DATA_WIDTH(DW)) u_reg_file_b(
        .clk(clk), .rd_addr(rd_addr[0]), .rd_data(rd_data_b),
        .wr_en(wr_en), .wr_addr(wr_addr), .wr_data(wr_data));

    // Compare rd_data of both instances with models.
    task check(input integer step, input string when);
        begin
            if (rd_data_a[0] !== model_a[rd_addr[0]] || rd_data_a[1] !== model_a[rd_addr[1]])
                $fatal(1, "RegFile A step %0d %s edge: rd_addr=%0d,%0d wr_en=%b wr_addr=%0d wr_data=%h got rd_data=%h,%h, expected %h,%h",
                       step, when, rd_addr[0], rd_addr[1], wr_en[0], wr_addr[0], wr_data[0],
                       rd_data_a[0], rd_data_a[1], model_a[rd_addr[0]], model_a[rd_addr[1]]);
            if (rd_data_b !== model_b[rd_addr[0]])
                $fatal(1, "RegFile B step %0d %s edge: rd_addr=%0d wr_en=%b wr_addr=%0d,%0d wr_data=%h,%h got rd_data=%h, expected %h",
                       step, when, rd_addr[0], wr_en, wr_addr[0], wr_addr[1], wr_data[0], wr_data[1],
                       rd_data_b, model_b[rd_addr[0]]);
        end
    endtask

    // One clock cycle: set inputs after falling edge, check before and after rising edge.
    task cycle(input integer step, input [AW-1:0] ra0, input [AW-1:0] ra1,
               input we0, input [AW-1:0] wa0, input [DW-1:0] d0,
               input we1, input [AW-1:0] wa1, input [DW-1:0] d1);
        begin
            @(negedge clk);
            rd_addr = {ra1, ra0}; wr_en = {we1, we0}; wr_addr = {wa1, wa0}; wr_data = {d1, d0};
            #1;
            check(step, "before");
            @(posedge clk);
            if (we0) model_a[wa0] = d0;
            if (we0) model_b[wa0] = d0;
            if (we1) model_b[wa1] = d1;  // port 1 after port 0: highest port wins
            #1;
            check(step, "after");
        end
    endtask

    initial begin
        rd_addr = 0; wr_en = 0; wr_addr = 0; wr_data = 0;

        // 1. Write every register at port 0, read it in the same cycle.
        for (i = 0; i < REGS; i = i + 1) begin
            value = i[DW-1:0] * 8'd37 + 8'd5;
            cycle(i, i[AW-1:0], i[AW-1:0], 1, i[AW-1:0], value, 0, 0, 0);
        end
        // 2. Read every register, ports read different registers.
        for (i = 0; i < REGS; i = i + 1) begin
            other_addr = REGS - 1 - i;
            cycle(100 + i, i[AW-1:0], other_addr[AW-1:0], 0, 0, 0, 0, 0, 0);
        end
        // 3. B: both write ports write the same register, port 1 wins.
        for (i = 0; i < REGS; i = i + 1) begin
            value = i[DW-1:0] * 8'd11 + 8'd200;
            cycle(200 + i, i[AW-1:0], i[AW-1:0], 1, i[AW-1:0], value, 1, i[AW-1:0], ~value);
        end
        // 4. B: write ports write different registers.
        for (i = 0; i < REGS; i = i + 1) begin
            other_addr = i + 1;
            value = i[DW-1:0] * 8'd13 + 8'd7;
            cycle(300 + i, i[AW-1:0], other_addr[AW-1:0], 1, i[AW-1:0], value, 1, other_addr[AW-1:0], ~value);
        end
        // 5. wr_en=0 does not write.
        cycle(400, 3'd3, 3'd4, 0, 3'd3, 8'hFF, 0, 3'd4, 8'hFF);
        cycle(401, 3'd3, 3'd4, 0, 3'd0, 8'h00, 0, 3'd0, 8'h00);
        // 6. Random cycles, every register was written in 1.
        seed = 1;
        for (i = 0; i < 1000; i = i + 1) begin
            r = $random(seed);
            cycle(1000 + i, r[AW-1:0], r[AW+3:4], r[0], r[AW+7:8], r[DW+15:16],
                  r[1], r[AW+11:12], r[DW+23:24]);
        end

        $display("PASS");
        $finish;
    end
endmodule

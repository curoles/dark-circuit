/* Test of RegFileSram block, made of behave or struct Sram1R1W.
 *
 * Two instances: RD_PORTS=2, and RD_PORTS=1 connected to read port 0 inputs.
 * Inputs change on falling edge, after every rising edge rd_data of both
 * instances is compared with model of the registers.
 * Stops at the first mismatch with $fatal.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module TbRegFileSram;
    localparam AW   = 3;
    localparam DW   = 8;
    localparam REGS = 1 << AW;

    wire                clk;
    reg  [1:0]          rd_en;
    reg  [1:0][AW-1:0]  rd_addr;
    wire [1:0][DW-1:0]  rd_data;
    wire [DW-1:0]       rd_data_1;  // read port of the RD_PORTS=1 instance
    reg                 wr_en;
    reg  [AW-1:0]       wr_addr;
    reg  [DW-1:0]       wr_data;

    reg  [DW-1:0] model [REGS];
    reg  [DW-1:0] exp0;  // unknown until the first read
    reg  [DW-1:0] exp1;
    reg  [DW-1:0] value;
    // Random word, only some of its bits are used.
    /* verilator lint_off UNUSEDSIGNAL */
    reg  [31:0]   r;
    integer       other_addr;
    /* verilator lint_on UNUSEDSIGNAL */
    integer i;
    integer seed;

    SimClkGen #(.HALF_PERIOD(5)) u_sim_clk_gen(.clk(clk));

    RegFileSram #(.RD_PORTS(2), .ADDR_WIDTH(AW), .DATA_WIDTH(DW)) u_reg_file_sram_2(
        .clk(clk), .rd_en(rd_en), .rd_addr(rd_addr), .rd_data(rd_data),
        .wr_en(wr_en), .wr_addr(wr_addr), .wr_data(wr_data));

    RegFileSram #(.RD_PORTS(1), .ADDR_WIDTH(AW), .DATA_WIDTH(DW)) u_reg_file_sram_1(
        .clk(clk), .rd_en(rd_en[0]), .rd_addr(rd_addr[0]), .rd_data(rd_data_1),
        .wr_en(wr_en), .wr_addr(wr_addr), .wr_data(wr_data));

    // One clock cycle: set inputs after falling edge, check after rising edge.
    task cycle(input integer step, input re0, input [AW-1:0] ra0, input re1, input [AW-1:0] ra1,
               input we, input [AW-1:0] wa, input [DW-1:0] d);
        begin
            @(negedge clk);
            rd_en = {re1, re0}; rd_addr = {ra1, ra0}; wr_en = we; wr_addr = wa; wr_data = d;
            @(posedge clk);
            if (re0) exp0 = model[ra0];  // read-first: old data
            if (re1) exp1 = model[ra1];
            if (we) model[wa] = d;
            #1;
            if (rd_data[0] !== exp0 || rd_data[1] !== exp1)
                $fatal(1, "RegFileSram 2 ports step %0d: rd_en=%b rd_addr=%0d,%0d wr_en=%b wr_addr=%0d wr_data=%h got rd_data=%h,%h, expected %h,%h",
                       step, rd_en, ra0, ra1, we, wa, d, rd_data[0], rd_data[1], exp0, exp1);
            if (rd_data_1 !== exp0)
                $fatal(1, "RegFileSram 1 port step %0d: rd_en=%b rd_addr=%0d wr_en=%b wr_addr=%0d wr_data=%h got rd_data=%h, expected %h",
                       step, re0, ra0, we, wa, d, rd_data_1, exp0);
        end
    endtask

    initial begin
        rd_en = 0; rd_addr = 0; wr_en = 0; wr_addr = 0; wr_data = 0;

        // 1. Write every register.
        for (i = 0; i < REGS; i = i + 1) begin
            value = i[DW-1:0] * 8'd37 + 8'd5;
            cycle(i, 0, 0, 0, 0, 1, i[AW-1:0], value);
        end
        // 2. Read every register back, ports read different registers.
        for (i = 0; i < REGS; i = i + 1) begin
            other_addr = REGS - 1 - i;
            cycle(100 + i, 1, i[AW-1:0], 1, other_addr[AW-1:0], 0, 0, 0);
        end
        // 3. Read and write different registers in the same cycle.
        for (i = 0; i < REGS; i = i + 1) begin
            other_addr = i + 1;
            value = i[DW-1:0] * 8'd11 + 8'd200;
            cycle(200 + i, 1, i[AW-1:0], 1, i[AW-1:0], 1, other_addr[AW-1:0], value);
        end
        // 4. Read and write the same register in the same cycle reads old data.
        cycle(300, 1, 3'd2, 1, 3'd2, 1, 3'd2, 8'hA5);
        cycle(301, 1, 3'd2, 1, 3'd2, 0, 3'd0, 8'h00);
        // 5. rd_en[k]=0 holds rd_data[k] of its port only, wr_en=0 does not write.
        cycle(400, 1, 3'd5, 0, 3'd6, 0, 3'd0, 8'h00);
        cycle(401, 0, 3'd6, 1, 3'd7, 0, 3'd0, 8'h00);
        cycle(402, 0, 3'd1, 0, 3'd1, 0, 3'd3, 8'hFF);
        cycle(403, 1, 3'd3, 1, 3'd3, 0, 3'd3, 8'hFF);
        // 6. Random cycles, every register was written in 1.
        seed = 1;
        for (i = 0; i < 1000; i = i + 1) begin
            r = $random(seed);
            cycle(1000 + i, r[0], r[AW+3:4], r[1], r[AW+7:8], r[2], r[AW+11:12], r[DW+15:16]);
        end

        $display("PASS");
        $finish;
    end
endmodule

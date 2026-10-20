/* Unit test of Mig2Regs.
 *
 * 1. Pipeline writes registers, two different registers read in the same cycle.
 * 2. A write to x0 is dropped, x0 reads 0 on both ports.
 * 3. A register written in a cycle reads the old value until rising edge, then the new.
 * 4. Halted: debug writes and reads, x0 is 0 also through debug, pipeline write is ignored.
 * 5. Running again: the pipeline reads the register debug wrote.
 * Inputs change on falling edge. Stops at the first mismatch with $fatal.
 */
module TbMig2Regs;
    import Mig2Pkg::*;

    wire        clk;
    logic       halt;
    reg_id_t    rs1;
    reg_id_t    rs2;
    wire [31:0] rs1_data;
    wire [31:0] rs2_data;
    logic       rd_we;
    reg_id_t    rd;
    logic [31:0] rd_data;
    reg_id_t    dbg_reg_id;
    logic       dbg_reg_wr;
    logic [31:0] dbg_reg_wdata;
    wire [31:0] dbg_reg_rdata;

    SimClkGen #(.HALF_PERIOD(5)) u_sim_clk_gen(.clk(clk));

    Mig2Regs u_mig2_regs(
        .clk(clk), .halt(halt),
        .rs1(rs1), .rs2(rs2), .rs1_data(rs1_data), .rs2_data(rs2_data),
        .rd_we(rd_we), .rd(rd), .rd_data(rd_data),
        .dbg_reg_id(dbg_reg_id), .dbg_reg_wr(dbg_reg_wr),
        .dbg_reg_wdata(dbg_reg_wdata), .dbg_reg_rdata(dbg_reg_rdata));

    // Pipeline writes register r with value v on the next rising edge.
    task automatic write(input [4:0] r, input [31:0] v);
        @(negedge clk);
        rd_we = 1; rd = r; rd_data = v;
        @(negedge clk);
        rd_we = 0;
    endtask

    // Read registers r1 and r2 on the pipeline ports and compare.
    task automatic expect_read(input [4:0] r1, input [4:0] r2, input [31:0] v1, input [31:0] v2);
        rs1 = r1; rs2 = r2; #1;
        if (rs1_data !== v1 || rs2_data !== v2)
            $fatal(1, "Mig2Regs: x%0d=%h x%0d=%h, expected %h %h", r1, rs1_data, r2, rs2_data, v1, v2);
    endtask

    // Debug reads register r and compares.
    task automatic expect_dbg(input [4:0] r, input [31:0] v);
        dbg_reg_id = r; #1;
        if (dbg_reg_rdata !== v)
            $fatal(1, "Mig2Regs: debug x%0d=%h, expected %h", r, dbg_reg_rdata, v);
    endtask

    initial begin
        halt = 0; rs1 = 0; rs2 = 0; rd_we = 0; rd = 0; rd_data = 0;
        dbg_reg_id = 0; dbg_reg_wr = 0; dbg_reg_wdata = 0;

        // 1. Pipeline writes, two reads in the same cycle.
        write(5'd1,  32'h1111_1111);
        write(5'd2,  32'h2222_2222);
        write(5'd31, 32'hffff_0031);
        expect_read(5'd1,  5'd2, 32'h1111_1111, 32'h2222_2222);
        expect_read(5'd31, 5'd1, 32'hffff_0031, 32'h1111_1111);

        // 2. x0: write dropped, reads 0.
        write(5'd0, 32'hdead_beef);
        expect_read(5'd0, 5'd0, 32'h0, 32'h0);

        // 3. Old value until rising edge, new value after it.
        @(negedge clk);
        rd_we = 1; rd = 5'd1; rd_data = 32'h0101_0101;
        expect_read(5'd1, 5'd0, 32'h1111_1111, 32'h0);
        @(posedge clk); #1;
        if (rs1_data !== 32'h0101_0101)
            $fatal(1, "Mig2Regs: x1=%h after rising edge, expected 01010101", rs1_data);
        @(negedge clk);
        rd_we = 0;

        // 4. Halted: debug owns the ports, pipeline write is ignored.
        halt = 1;
        rd_we = 1; rd = 5'd2; rd_data = 32'hbad0_bad0;
        dbg_reg_wr = 1; dbg_reg_id = 5'd3; dbg_reg_wdata = 32'h3333_3333;
        @(negedge clk);
        dbg_reg_id = 5'd0; dbg_reg_wdata = 32'hffff_ffff;  // debug write to x0 is dropped too
        @(negedge clk);
        dbg_reg_wr = 0; rd_we = 0;
        expect_dbg(5'd3, 32'h3333_3333);
        expect_dbg(5'd2, 32'h2222_2222);
        expect_dbg(5'd0, 32'h0);

        // 5. Running again: the pipeline reads what debug wrote.
        halt = 0;
        expect_read(5'd3, 5'd2, 32'h3333_3333, 32'h2222_2222);

        $display("PASS");
        $finish;
    end
endmodule

/* Test of SimRAM with a RISC-V program from the GNU toolchain.
 *
 * sim_ram_riscv.S is built and converted by objcopy -O verilog into the file
 * given by plusarg +hex=<file>. load() of the file, then words at addresses
 * 0x00..0x10 must be the RV32I encodings of the program instructions
 * (from the RISC-V spec), and words at 0x80, 0x84 the data words.
 * Stops at the first mismatch with $fatal.
 */
module TbSimRamRiscv;
    localparam AW    = 8;  // 256 bytes
    localparam NR    = 7;  // number of checked words

    wire          clk;
    reg           rd_en;
    reg  [AW-1:2] rd_addr;
    wire [31:0]   rd_data;
    // Output is not checked, every read is one clock.
    /* verilator lint_off UNUSEDSIGNAL */
    wire          rd_valid;
    /* verilator lint_on UNUSEDSIGNAL */

    reg  [AW-1:0] addr [NR];
    reg  [31:0]   word [NR];
    string        hex;
    integer       i;

    SimClkGen #(.HALF_PERIOD(5)) u_sim_clk_gen(.clk(clk));

    SimRAM #(.DATA_SIZE(4), .ADDR_WIDTH(AW)) u_sim_ram(
        .clk(clk), .rd_en(rd_en), .rd_addr(rd_addr), .wr_en(1'b0), .wr_addr({(AW-2){1'b0}}),
        .wr_data(32'h0), .wr_strb(4'b0000), .rd_data(rd_data), .rd_valid(rd_valid));

    initial begin
        addr[0] = 8'h00; word[0] = 32'h00500093;  // addi x1, x0, 5
        addr[1] = 8'h04; word[1] = 32'h00700113;  // addi x2, x0, 7
        addr[2] = 8'h08; word[2] = 32'h002081B3;  // add  x3, x1, x2
        addr[3] = 8'h0C; word[3] = 32'h04302023;  // sw   x3, 0x40(x0)
        addr[4] = 8'h10; word[4] = 32'h00000073;  // ecall
        addr[5] = 8'h80; word[5] = 32'h12345678;  // .tbdata
        addr[6] = 8'h84; word[6] = 32'hCAFEF00D;
        rd_en = 0; rd_addr = 0;

        if (!$value$plusargs("hex=%s", hex))
            $fatal(1, "SimRAM RISC-V: plusarg +hex=<file> is missing");
        if (u_sim_ram.load(hex, u_sim_ram.VLOG_HEX_FORMAT) != 1)
            $fatal(1, "SimRAM RISC-V: load() of %s returned 0", hex);

        for (i = 0; i < NR; i = i + 1) begin
            @(negedge clk);
            rd_en = 1; rd_addr = addr[i][AW-1:2];
            @(posedge clk); #1;
            if (rd_data !== word[i])
                $fatal(1, "SimRAM RISC-V: word at %h got %h, expected %h", addr[i], rd_data, word[i]);
        end

        $display("PASS");
        $finish;
    end
endmodule

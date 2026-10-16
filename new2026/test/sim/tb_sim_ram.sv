/* Test of SimRAM simulation RAM model.
 *
 * 1. 4-byte words: write words, read them back, rd_valid follows rd_en.
 * 2. 4-byte words: read and write of the same word in one cycle reads old data.
 * 3. 1-byte words: write bytes, read them back.
 * 4. load() of hex file with bytes 11 22 .. 88 gives little-endian words.
 *
 * Inputs change on falling edge, outputs are checked after rising edge.
 * Stops at the first mismatch with $fatal.
 */
module TbSimRam;
    localparam AW    = 6;   // 64 bytes
    localparam WORDS = 16;  // 4-byte words

    wire          clk;

    reg           rd_en4;
    reg           wr_en4;
    reg  [AW-1:2] rd_addr4;
    reg  [AW-1:2] wr_addr4;
    reg  [31:0]   wr_data4;
    wire [31:0]   rd_data4;
    wire          rd_valid4;
    reg  [31:0]   model4 [WORDS];
    reg  [31:0]   exp4;  // unknown until the first read

    reg           rd_en1;
    reg           wr_en1;
    reg  [AW-1:0] rd_addr1;
    reg  [AW-1:0] wr_addr1;
    reg  [7:0]    wr_data1;
    wire [7:0]    rd_data1;
    wire          rd_valid1;

    integer i;
    integer fd;

    SimClkGen #(.HALF_PERIOD(5)) u_sim_clk_gen(.clk(clk));

    SimRAM #(.DATA_SIZE(4), .ADDR_WIDTH(AW)) u_sim_ram_4(
        .clk(clk), .rd_en(rd_en4), .rd_addr(rd_addr4), .wr_en(wr_en4), .wr_addr(wr_addr4),
        .wr_data(wr_data4), .rd_data(rd_data4), .rd_valid(rd_valid4));

    SimRAM #(.DATA_SIZE(1), .ADDR_WIDTH(AW)) u_sim_ram_1(
        .clk(clk), .rd_en(rd_en1), .rd_addr(rd_addr1), .wr_en(wr_en1), .wr_addr(wr_addr1),
        .wr_data(wr_data1), .rd_data(rd_data1), .rd_valid(rd_valid1));

    // One clock cycle of the 4-byte RAM with model check.
    task cycle4(input integer step, input re, input [AW-1:2] ra, input we, input [AW-1:2] wa, input [31:0] d);
        begin
            @(negedge clk);
            rd_en4 = re; rd_addr4 = ra; wr_en4 = we; wr_addr4 = wa; wr_data4 = d;
            @(posedge clk);
            if (re) exp4 = model4[ra];  // read-first: old data
            if (we) model4[wa] = d;
            #1;
            if (rd_data4 !== exp4 || rd_valid4 !== re)
                $fatal(1, "SimRAM 4 step %0d: rd_en=%b rd_addr=%0d wr_en=%b wr_addr=%0d wr_data=%h got rd_data=%h rd_valid=%b, expected %h %b",
                       step, re, ra, we, wa, d, rd_data4, rd_valid4, exp4, re);
        end
    endtask

    initial begin
        rd_en4 = 0; wr_en4 = 0; rd_addr4 = 0; wr_addr4 = 0; wr_data4 = 0;
        rd_en1 = 0; wr_en1 = 0; rd_addr1 = 0; wr_addr1 = 0; wr_data1 = 0;

        // 1. Write every word, read every word back.
        for (i = 0; i < WORDS; i = i + 1)
            cycle4(i, 0, 0, 1, i[AW-3:0], 32'hC0DE0000 | i[31:0]);
        for (i = 0; i < WORDS; i = i + 1)
            cycle4(100 + i, 1, i[AW-3:0], 0, 0, 0);
        cycle4(200, 0, 0, 0, 0, 0);  // rd_valid goes 0

        // 2. Read and write of the same word reads old data.
        cycle4(300, 1, 4'd5, 1, 4'd5, 32'hA5A5A5A5);
        cycle4(301, 1, 4'd5, 0, 4'd0, 32'h0);

        // 3. 1-byte words: write every byte, read every byte back.
        for (i = 0; i < 2**AW; i = i + 1) begin
            @(negedge clk);
            wr_en1 = 1; wr_addr1 = i[AW-1:0]; wr_data1 = i[7:0] ^ 8'h5A;
        end
        @(negedge clk);
        wr_en1 = 0;
        for (i = 0; i < 2**AW; i = i + 1) begin
            @(negedge clk);
            rd_en1 = 1; rd_addr1 = i[AW-1:0];
            @(posedge clk); #1;
            if (rd_data1 !== (i[7:0] ^ 8'h5A) || rd_valid1 !== 1'b1)
                $fatal(1, "SimRAM 1: addr=%0d got rd_data=%h rd_valid=%b, expected %h", i, rd_data1, rd_valid1, i[7:0] ^ 8'h5A);
        end
        @(negedge clk);
        rd_en1 = 0;

        // 4. load() bytes 11 22 .. 88 from @0: words are little-endian.
        fd = $fopen("sim_ram_load.hex", "w");
        $fwrite(fd, "@0\n11\n22\n33\n44\n55\n66\n77\n88\n");
        $fclose(fd);
        if (u_sim_ram_4.load("sim_ram_load.hex", 0) != 1)
            $fatal(1, "SimRAM: load() returned 0");
        model4[0] = 32'h44332211;
        model4[1] = 32'h88776655;
        cycle4(400, 1, 4'd0, 0, 4'd0, 32'h0);
        cycle4(401, 1, 4'd1, 0, 4'd0, 32'h0);

        $display("PASS");
        $finish;
    end
endmodule

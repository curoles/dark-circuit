/* Test of SimROM simulation ROM model.
 *
 * 1. load() of hex file with bytes 11 22 .. 88: 4-byte words are little-endian,
 *    1-byte words are the bytes.
 * 2. load() of binary file with bytes 11 22 33 44 at byte address 4.
 * 3. load() with unknown format returns 0.
 * 4. data gets word at new addr 1 clock later.
 *
 * Stops at the first mismatch with $fatal.
 */
module TbSimRom;
    localparam AW = 4;  // 16 bytes

    wire          clk;
    reg  [AW-1:2] addr4;
    wire [31:0]   data4;
    reg  [AW-1:0] addr1;
    wire [7:0]    data1;
    reg  [AW-1:2] addr4b;
    wire [31:0]   data4b;
    integer i;
    integer fd;

    SimClkGen #(.HALF_PERIOD(5)) u_sim_clk_gen(.clk(clk));

    SimROM #(.DATA_SIZE(4), .ADDR_WIDTH(AW)) u_sim_rom_4  (.clk(clk), .addr(addr4),  .data(data4));
    SimROM #(.DATA_SIZE(1), .ADDR_WIDTH(AW)) u_sim_rom_1  (.clk(clk), .addr(addr1),  .data(data1));
    SimROM #(.DATA_SIZE(4), .ADDR_WIDTH(AW)) u_sim_rom_bin(.clk(clk), .addr(addr4b), .data(data4b));

    initial begin
        addr4 = 0; addr1 = 0; addr4b = 0;

        // 1., 2. Files are written here and loaded.
        fd = $fopen("sim_rom_load.hex", "w");
        $fwrite(fd, "@0\n11\n22\n33\n44\n55\n66\n77\n88\n");
        $fclose(fd);
        fd = $fopen("sim_rom_load.bin", "w");
        $fwrite(fd, "@4\n00010001\n00100010\n00110011\n01000100\n");
        $fclose(fd);
        if (u_sim_rom_4.load("sim_rom_load.hex", 0) != 1)   $fatal(1, "SimROM 4: load() of hex file returned 0");
        if (u_sim_rom_1.load("sim_rom_load.hex", 0) != 1)   $fatal(1, "SimROM 1: load() of hex file returned 0");
        if (u_sim_rom_bin.load("sim_rom_load.bin", 1) != 1) $fatal(1, "SimROM bin: load() of binary file returned 0");
        // 3. Unknown format.
        if (u_sim_rom_4.load("sim_rom_load.hex", 2) != 0)   $fatal(1, "SimROM 4: load() with unknown format returned 1");

        // 4-byte words are little-endian.
        @(negedge clk); addr4 = 2'd0;
        @(posedge clk); #1;
        if (data4 !== 32'h44332211) $fatal(1, "SimROM 4: word 0 got %h, expected 44332211", data4);
        // 4. New addr: data is old until rising edge, then new word.
        @(negedge clk); addr4 = 2'd1; #1;
        if (data4 !== 32'h44332211) $fatal(1, "SimROM 4: data changed before clock, got %h", data4);
        @(posedge clk); #1;
        if (data4 !== 32'h88776655) $fatal(1, "SimROM 4: word 1 got %h, expected 88776655", data4);

        // 1-byte words are the bytes 11 22 .. 88.
        for (i = 0; i < 8; i = i + 1) begin
            @(negedge clk); addr1 = i[AW-1:0];
            @(posedge clk); #1;
            if (data1 !== 8'h11 * (i[7:0] + 8'd1))
                $fatal(1, "SimROM 1: byte %0d got %h, expected %h", i, data1, 8'h11 * (i[7:0] + 8'd1));
        end

        // Binary file: bytes 11 22 33 44 at byte address 4 are word 1.
        @(negedge clk); addr4b = 2'd1;
        @(posedge clk); #1;
        if (data4b !== 32'h44332211) $fatal(1, "SimROM bin: word 1 got %h, expected 44332211", data4b);

        $display("PASS");
        $finish;
    end
endmodule

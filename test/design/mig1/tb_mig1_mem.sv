/* Test of Mig1Cpu memories: load() puts program mem.S into instruction and data memory.
 *
 * mem.S is linked with sw/riscv/mig1.ld: 5 instructions at 0x00..0x10 and data word
 * 0x12345678 in .rodata at 0x14. After load() of +hex=<file>, both memories must
 * hold these words, read with peek() as little-endian bytes. Then 20 cycles:
 * the core (still a stub) must not stop.
 * Stops at the first mismatch with $fatal.
 */
module TbMig1Mem;
    import Mig1Pkg::*;

    localparam AW = MIG1_MEM_ADDR_WIDTH;
    localparam NR = 6;  // number of checked words

    wire       clk;
    wire       rst_n;
    wire       halt;
    wire       illegal;
    // Not checked yet, the core is a stub.
    /* verilator lint_off UNUSEDSIGNAL */
    retire_t   retire;
    /* verilator lint_on UNUSEDSIGNAL */

    reg [AW-1:0] addr [NR];
    reg [31:0]   word [NR];
    string       hex;
    integer      i;

    SimClkGen #(.HALF_PERIOD(5)) u_sim_clk_gen(.clk(clk));
    SimRstGen #(.CYCLES(3))      u_sim_rst_gen(.clk(clk), .rst_n(rst_n));

    Mig1Cpu u_mig1_cpu(.clk(clk), .rst_n(rst_n), .halt(halt), .illegal(illegal), .retire(retire));

    // Word at byte address a of instruction or data memory, little-endian.
    function automatic [31:0] imem_word(input [AW-1:0] a);
        for (int b = 0; b < 4; b++)
            imem_word[8*b +: 8] = u_mig1_cpu.u_imem.peek(a + b[AW-1:0]);
    endfunction

    function automatic [31:0] dmem_word(input [AW-1:0] a);
        for (int b = 0; b < 4; b++)
            dmem_word[8*b +: 8] = u_mig1_cpu.u_dmem.peek(a + b[AW-1:0]);
    endfunction

    initial begin
        addr[0] = 'h00; word[0] = 32'h00500093;  // addi x1, x0, 5
        addr[1] = 'h04; word[1] = 32'h00700113;  // addi x2, x0, 7
        addr[2] = 'h08; word[2] = 32'h002081B3;  // add  x3, x1, x2
        addr[3] = 'h0C; word[3] = 32'h04302023;  // sw   x3, 0x40(x0)
        addr[4] = 'h10; word[4] = 32'h00000073;  // ecall
        addr[5] = 'h14; word[5] = 32'h12345678;  // .rodata

        if (!$value$plusargs("hex=%s", hex))
            $fatal(1, "Mig1 mem: plusarg +hex=<file> is missing");
        if (u_mig1_cpu.load(hex) != 1)
            $fatal(1, "Mig1 mem: load() of %s returned 0", hex);

        for (i = 0; i < NR; i = i + 1) begin
            if (imem_word(addr[i]) !== word[i])
                $fatal(1, "Mig1 mem: imem word at %h got %h, expected %h", addr[i], imem_word(addr[i]), word[i]);
            if (dmem_word(addr[i]) !== word[i])
                $fatal(1, "Mig1 mem: dmem word at %h got %h, expected %h", addr[i], dmem_word(addr[i]), word[i]);
        end

        repeat (20) begin
            @(posedge clk); #1;
            if (halt !== 1'b0 || illegal !== 1'b0)
                $fatal(1, "Mig1 mem: core stopped, halt=%b illegal=%b", halt, illegal);
        end

        $display("PASS");
        $finish;
    end
endmodule

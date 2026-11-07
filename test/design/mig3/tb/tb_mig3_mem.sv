/* Test of Mig3Cpu's memory: load() puts program mem.S into the memory.
 *
 * mem.S is linked with sw/riscv/mig3.ld: 5 instructions at 0x00..0x10 and data word
 * 0x12345678 in .rodata at 0x14. After load() of +hex=<file>, the memory must
 * hold these words, read with peek() as little-endian bytes. Running programs is
 * tested by TbMig3.
 * Stops at the first mismatch with $fatal.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module TbMig3Mem;
    import Mig3Pkg::*;

    localparam AW = MIG3_CFG.mem_addr_width;
    localparam NR = 6;  // number of checked words

    logic          clk;
    logic          rst_n;
    dbg_req_t      dbg_req;     // idle
    // Not checked: this test only loads memories.
    /* verilator lint_off UNUSEDSIGNAL */
    logic          halt;
    retire_t       retire;
    pipe_trace_t   pipe_trace;
    dbg_rsp_t      dbg_rsp;
    /* verilator lint_on UNUSEDSIGNAL */

    word_t         word [NR];   // word i is at byte address 4 * i
    logic [AW-1:0] addr;        // byte address of the checked word
    string         hex;
    integer        i;

    SimClkGen #(.HALF_PERIOD(5)) u_sim_clk_gen(.clk);
    SimRstGen #(.CYCLES(3))      u_sim_rst_gen(.clk, .rst_n);

    assign dbg_req = '0;

    Mig3Cpu u_mig3_cpu(.clk, .rst_n, .uncached(1'b0), .irq_src('0), .halt, .retire, .pipe_trace,
                       .dbg_req,
                       .dbg_rsp);

    // Word at byte address a of the memory, little-endian.
    function automatic word_t mem_word(input logic [AW-1:0] a);
        for (int b = 0; b < 4; b++)
            mem_word[8*b +: 8] = u_mig3_cpu.u_mem.peek(a + b[AW-1:0]);
    endfunction

    initial begin
        word[0] = 32'h0050_0093;  // addi x1, x0, 5
        word[1] = 32'h0070_0113;  // addi x2, x0, 7
        word[2] = 32'h0020_81b3;  // add  x3, x1, x2
        word[3] = 32'h0430_2023;  // sw   x3, 0x40(x0)
        word[4] = 32'h0000_0073;  // ecall
        word[5] = 32'h1234_5678;  // .rodata

        if (!$value$plusargs("hex=%s", hex))
            $fatal(1, "Mig3 mem: plusarg +hex=<file> is missing");
        if (u_mig3_cpu.load(hex) != 1)
            $fatal(1, "Mig3 mem: load() of %s returned 0", hex);

        for (i = 0; i < NR; i = i + 1) begin
            addr = AW'(4 * i);
            if (mem_word(addr) !== word[i])
                $fatal(1, "Mig3 mem: word at %h got %h, expected %h",
                       addr, mem_word(addr), word[i]);
        end

        $display("PASS");
        $finish;
    end
endmodule

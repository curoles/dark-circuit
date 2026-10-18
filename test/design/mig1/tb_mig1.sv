/* Testbench of Mig1Cpu running a program.
 *
 * Loads +hex=<file>, releases reset and runs until the core halts.
 * Checks of every retired instruction:
 * - retire.insn is the imem word at retire.pc: fetch gets the right instruction,
 * - the first retired pc is the reset address,
 * - nothing retires after halt,
 * - no X or Z in retire (Icarus only, Verilator is 2-state),
 * - with +expect_sequential: every pc is the previous pc + 4 (straight-line code).
 * Register writes of retire (rd, rd_data) are kept in a shadow copy of the registers.
 * At the end: halt with illegal=0 passes, illegal=1 fails; with +expect_illegal it is
 * the other way around, and a resume must not restart the core (illegal=1 is final). And
 * - with +expect_retired=<n>: n instructions retired,
 * - with +expect_halt_pc=<hex byte address without 0x>: the core halted there,
 * - with +expect_regs: the shadow registers have the values of the table that the
 *   program puts right after the halting instruction (EBREAK, or the instruction
 *   that made illegal=1): number of entries n, then n pairs of
 *   words register, value; a register in the table that was never written fails,
 * - with +expect_mem_unchanged: dmem equals imem byte for byte; Mig1Cpu loads the
 *   same image into both, so this shows that nothing was stored.
 * With +resumes=<n> the testbench is a debugger at the first n halts after EBREAK:
 * it reads a0 (x10) through the debug port (must equal the shadow), writes
 * a0 + 0x100, and resumes the core; the halt after that ends the run. The shadow registers
 * follow debug writes too.
 * Other plusargs: +trace=<file> writes every retired instruction, register write and
 * debug action into <file>, +trace alone prints them; +max_cycles=<n> (default 100000).
 * Stops at the first failure with $fatal.
 */
module TbMig1;
    import Mig1Pkg::*;

    localparam AW = MIG1_MEM_ADDR_WIDTH;

    wire             clk;
    wire             rst_n;
    wire             halt;
    wire             illegal;
    retire_t         retire;
    wire [WIDTH-1:0] retire_pc;     // byte address
    wire [WIDTH-1:0] halt_pc;       // byte address
    dbg_req_t        dbg_req;
    dbg_rsp_t        dbg_rsp;

    string           hex;
    string           trace_file;
    integer          trace_fd;      // 0: no trace
    reg              expect_sequential;
    integer          max_cycles;
    integer          expect_retired; // -1: not checked
    reg              expect_illegal;
    reg              check_halt_pc;
    reg [WIDTH-1:0]  expect_halt_pc;
    reg              expect_regs;
    reg              expect_mem_unchanged;
    reg [WIDTH-1:0]  shadow [32];   // registers written by retired instructions
    reg [31:0]       written;       // bit r: shadow[r] was written
    integer          cycle;
    integer          retired;
    reg [WIDTH-1:0]  prev_pc;
    reg              halted;
    integer          resumes;       // halts after EBREAK left to resume
    reg              done;

    SimClkGen #(.HALF_PERIOD(5)) u_sim_clk_gen(.clk(clk));
    SimRstGen #(.CYCLES(3))      u_sim_rst_gen(.clk(clk), .rst_n(rst_n));

    Mig1Cpu u_mig1_cpu(.clk(clk), .rst_n(rst_n), .halt(halt), .illegal(illegal), .retire(retire),
                       .dbg_req(dbg_req), .dbg_rsp(dbg_rsp));

    assign retire_pc = {retire.pc, {IADDR_START{1'b0}}};
    assign halt_pc   = {dbg_rsp.halt_pc, {IADDR_START{1'b0}}};

    // Word of imem at byte address a, little-endian; imem has AW address bits.
    function automatic [31:0] imem_word(input [AW-1:0] a);
        for (int b = 0; b < 4; b++)
            imem_word[8*b +: 8] = u_mig1_cpu.u_imem.peek(a + b[AW-1:0]);
    endfunction

    // +expect_mem_unchanged: every byte of dmem equals the byte of imem.
    task automatic check_mem_unchanged;
        logic [7:0] i;
        logic [7:0] d;
        for (int a = 0; a < (1 << AW); a++) begin
            i = u_mig1_cpu.u_imem.peek(a[AW-1:0]);
            d = u_mig1_cpu.u_dmem.peek(a[AW-1:0]);
            if (d !== i)
                $fatal(1, "Mig1: dmem byte at %h is %h, image has %h", a[AW-1:0], d, i);
        end
    endtask

    // +expect_regs: compare the shadow registers with the table after the halting
    // instruction at halt_pc.
    task automatic check_regs;
        logic [WIDTH-1:0] a;
        logic [WIDTH-1:0] n;
        logic [WIDTH-1:0] r;
        logic [WIDTH-1:0] value;
        logic [WIDTH-1:0] got;
        a = halt_pc + 4;
        n = imem_word(a[AW-1:0]);
        if (n == 0 || n > 32)
            $fatal(1, "Mig1: +expect_regs: %0d entries at %h, no table after the halting instruction?", n, a);
        repeat (n) begin
            a = a + 4;
            r = imem_word(a[AW-1:0]);
            a = a + 4;
            value = imem_word(a[AW-1:0]);
            if (r > 31)
                $fatal(1, "Mig1: +expect_regs: register %0d at %h", r, a - 4);
            if (r != 0 && !written[r[4:0]])
                $fatal(1, "Mig1: x%0d was never written, expected %h", r, value);
            got = (r == 0) ? '0 : shadow[r[4:0]];
            if (got !== value)
                $fatal(1, "Mig1: x%0d is %h, expected %h", r, got, value);
        end
    endtask

    // Debugger at a halt after EBREAK: read a0, write a0 + 0x100, resume. One clock
    // each for the write and the resume; the shadow follows the write in the always
    // block. Not a0 + 1: that is what the EBREAK in EX computes (rs1 + imm, rs1 is
    // read port 0 = x10), so a debug write that is lost would not be noticed.
    task automatic debug_and_resume;
        logic [WIDTH-1:0] a0;
        if (imem_word(halt_pc[AW-1:0]) !== INSN_EBREAK)
            $fatal(1, "Mig1: halted at %h, it is not EBREAK", halt_pc);
        dbg_req.reg_addr = 10;
        #1;
        a0 = dbg_rsp.reg_rdata;
        if (written[10] && a0 !== shadow[10])
            $fatal(1, "Mig1: debug read of x10 gave %h, expected %h", a0, shadow[10]);
        dbg_req.reg_wdata = a0 + 32'h100;
        dbg_req.reg_wr    = 1'b1;
        @(posedge clk); #1;
        cycle = cycle + 1;
        dbg_req.reg_wr    = 1'b0;
        dbg_req.resume    = 1'b1;
        @(posedge clk); #1;
        cycle = cycle + 1;
        dbg_req.resume    = 1'b0;
    endtask

    // Checks of every retired instruction, values of the cycle before the rising edge;
    // register writes of the debugger.
    always @(posedge clk) begin
        if (rst_n && retire.valid) begin
`ifndef VERILATOR
            if ($isunknown(retire))
                $fatal(1, "Mig1: X or Z in retire: %h", retire);
`endif
            if (halted)
                $fatal(1, "Mig1: instruction at %h retired after halt", retire_pc);
            if (retired == 0 && retire_pc !== MIG1_RST_ADDR)
                $fatal(1, "Mig1: first instruction at %h, expected reset address %h", retire_pc, MIG1_RST_ADDR);
            if (expect_sequential && retired > 0 && retire_pc !== prev_pc + 4)
                $fatal(1, "Mig1: pc %h after %h, expected %h", retire_pc, prev_pc, prev_pc + 4);
            if (retire.insn !== imem_word(retire_pc[AW-1:0]))
                $fatal(1, "Mig1: insn %h at pc %h, imem has %h", retire.insn, retire_pc, imem_word(retire_pc[AW-1:0]));
            if (trace_fd != 0 && retire.rd != 0)
                $fdisplay(trace_fd, "%8d pc=%h insn=%h x%0d <= %h", cycle, retire_pc, retire.insn, retire.rd, retire.rd_data);
            else if (trace_fd != 0)
                $fdisplay(trace_fd, "%8d pc=%h insn=%h", cycle, retire_pc, retire.insn);
            if (retire.rd != 0) begin
                shadow[retire.rd]  <= retire.rd_data;
                written[retire.rd] <= 1'b1;
            end
            prev_pc <= retire_pc;
            retired <= retired + 1;
        end
        if (halt && dbg_req.reg_wr && dbg_req.reg_addr != 0) begin
            if (trace_fd != 0)
                $fdisplay(trace_fd, "%8d debug x%0d <= %h", cycle, dbg_req.reg_addr, dbg_req.reg_wdata);
            shadow[dbg_req.reg_addr]  <= dbg_req.reg_wdata;
            written[dbg_req.reg_addr] <= 1'b1;
        end else if (halt && dbg_req.resume && trace_fd != 0)
            $fdisplay(trace_fd, "%8d resume", cycle);
    end

    initial begin
        retired = 0;
        halted  = 0;
        cycle   = 0;
        prev_pc = 0;
        written = 0;
        dbg_req = '0;
        if (!$value$plusargs("resumes=%d", resumes)) resumes = 0;
        expect_sequential = $test$plusargs("expect_sequential");
        expect_regs       = $test$plusargs("expect_regs");
        expect_mem_unchanged = $test$plusargs("expect_mem_unchanged");
        if (!$value$plusargs("max_cycles=%d", max_cycles))         max_cycles = 100000;
        if (!$value$plusargs("expect_retired=%d", expect_retired)) expect_retired = -1;
        expect_illegal    = $test$plusargs("expect_illegal");
        check_halt_pc = $value$plusargs("expect_halt_pc=%h", expect_halt_pc);

        // +trace=<file> writes the trace into <file>, +trace alone prints it.
        if ($value$plusargs("trace=%s", trace_file)) begin
            trace_fd = $fopen(trace_file, "w");
            if (trace_fd == 0)
                $fatal(1, "Mig1: can not open trace file %s", trace_file);
            $display("Mig1: trace in %s", trace_file);
        end else if ($test$plusargs("trace"))
            trace_fd = 32'h8000_0001;   // stdout
        else
            trace_fd = 0;

        if (!$value$plusargs("hex=%s", hex))
            $fatal(1, "Mig1: plusarg +hex=<file> is missing");
        if (u_mig1_cpu.load(hex) != 1)
            $fatal(1, "Mig1: load() of %s returned 0", hex);

        @(posedge rst_n);
        done = 0;
        while (!done) begin
            while (!halt && !illegal) begin
                @(posedge clk); #1;
                cycle = cycle + 1;
                if (cycle > max_cycles)
                    $fatal(1, "Mig1: no halt after %0d cycles, %0d instructions retired", max_cycles, retired);
            end
            halted = 1;
            if (illegal || resumes == 0)
                done = 1;
            else begin
                debug_and_resume();
                resumes = resumes - 1;
                halted  = 0;
            end
        end
        if (illegal && !expect_illegal)
            $fatal(1, "Mig1: illegal=1 at %h, last retired pc %h", halt_pc, prev_pc);
        if (!illegal && expect_illegal)
            $fatal(1, "Mig1: halted at %h with illegal=0, +expect_illegal", halt_pc);
        if (illegal) begin
            dbg_req.resume = 1'b1;
            @(posedge clk); #1;
            dbg_req.resume = 1'b0;
        end

        repeat (5) @(posedge clk);  // nothing may retire after halt
        if (!halt)
            $fatal(1, "Mig1: core runs again after the halt at %h", halt_pc);
        if (expect_retired >= 0 && retired != expect_retired)
            $fatal(1, "Mig1: %0d instructions retired, expected %0d", retired, expect_retired);
        if (check_halt_pc && halt_pc !== expect_halt_pc)
            $fatal(1, "Mig1: halted at %h, expected %h", halt_pc, expect_halt_pc);
        if (expect_regs)
            check_regs();
        if (expect_mem_unchanged)
            check_mem_unchanged();
        $display("PASS: %0d instructions retired in %0d cycles, halted at %h", retired, cycle, halt_pc);
        if (trace_file.len() != 0)
            $fclose(trace_fd);
        $finish;
    end
endmodule

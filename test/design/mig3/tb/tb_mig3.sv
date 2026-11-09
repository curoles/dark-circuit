/* Testbench of Mig3Cpu running a program.
 *
 * Loads +hex=<file>, releases reset and runs until the core halts.
 * Checks of every retired instruction against the program, the memories and a shadow
 * copy of the registers, and the retire lines of the trace: TbMig3RetireCheck
 * (+expect_sequential: straight-line code). Traps are allowed with +expect_trap.
 * The testbench is the debugger: dbg_req.ebreak_halt=1, so EBREAK halts the core
 * (with +first_ebreak_traps it is 0 until an EBREAK has trapped, then 1).
 * At the end the core must be halted, and
 * - with +expect_trap: at least one trap happened,
 * - with +expect_retired=<n>: n instructions retired,
 * - with +expect_halt_pc=<hex byte address without 0x>: the core halted there,
 * - with +expect_regs: the shadow registers have the values of the table that the
 *   program puts right after the halting EBREAK: number of entries n, then n pairs of
 *   words register, value; a register in the table that was never written fails,
 * - with +expect_mem_unchanged: the memory equals the image load() put into it, byte for
 *   byte, so this shows that nothing was stored,
 * - with +riscv_test: the program is a riscv-tests test with its standard environment
 *   (env/p). It ends with a store to the word tohost, address from +symbols=<file> (nm
 *   output of the program): 1 is pass, (case << 1) | 1 is case `case` failed. The run
 *   ends at that store, the core does not halt (the environment loops). Traps are
 *   allowed: the environment probes CSRs Mig3 does not have, and an unexpected trap
 *   makes the test fail through tohost. An MRET must retire before the store: the
 *   environment enters the test body with MRET, and before that it reports a pass
 *   on its own when its XLEN check (a BLTZ) goes the wrong way, as on a broken core.
 * With +resumes=<n> the testbench is a debugger at the first n halts after EBREAK: it
 * checks a0 (x10) against the shadow, changes it through the debug port and resumes the
 * core; the halt after that ends the run. The shadow registers follow debug writes too.
 * Semihosting: an EBREAK between slli x0,x0,0x1f and srai x0,x0,7 is a semihosting call
 * (RISC-V semihosting spec), done by the testbench, which resumes the core; these halts
 * do not count for +resumes. SYS_EXIT and SYS_EXIT_EXTENDED end the run with an exit
 * status: with +expect_exit=<n> it must be n, without it 0.
 * +no_debugger: dbg_req.ebreak_halt=0 for the whole run, EBREAK traps.
 * The debug port and the semihosting calls: TbMig3Debugger.
 * Other plusargs: +trace=<file> writes every retired instruction, register write,
 * debug action and semihosting call into <file>, +trace alone prints them;
 * +max_pipeline_cycles=<n>: the pipeline cycles (TbMig3BubbleCheck: the cycles minus the
 * imem and dmem bubbles) must be at most n, the cycle ceiling of a test that counts cycles;
 * +max_cycles=<n> (default 100000) only stops a run that does not end;
 * +mem_latency=<ready %>,<fast %>,<fast min>,<fast max>,<slow min>,<slow max>: how the memory
 * of Mig3Cpu answers (SimLatencyRAM configure()), without it latency 1 and always ready.
 * +irq_random=<seed>: TbMig3Irq, a device, raises its interrupt, source 1 of the PLIC of
 * Mig3Cpu, at random times (+irq_max_gap=<n>) and drops it when the program acknowledges
 * it: a store to its word irq_claim (address from +symbols); without it the line stays 0.
 * The UART of Mig3Cpu: its tx goes into SimUartRx, a console at the boot rate
 * (MIG3_CFG.uart.div_rst + 1 clocks a bit, 8N1), which prints every character; its rx stays
 * idle (1). Before a semihosting call and at the end of the run the testbench waits until the
 * line has been idle for a frame, so the characters still in the UART's FIFO are printed
 * first; a framing error on it fails the run (a program at another rate).
 * +uncached: every request of the core bypasses its caches (Mig3Caches), so the program sees
 * the memory's own timing: for tests that count cycles.
 * Bubbles, their checks, their trace lines and the count per reason at the end:
 * TbMig3BubbleCheck.
 * Pipeline view, checked against pipe_trace, and its Konata log (+kanata=<file>):
 * TbMig3PipeView.
 * Stops at the first failure with $fatal.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module TbMig3;
    import Mig3Pkg::*;
    import RiscvInstrPkg::*;

    localparam AW = MIG3_CFG.mem_addr_width;
    localparam UART_CLKS  = MIG3_CFG.uart.div_rst + 1;  // clocks of a bit on the UART's line
    localparam UART_FRAME = 10 * UART_CLKS;              // ... of a frame, 8N1

    logic        clk;
    logic        rst_n;
    logic        halt;
    retire_t     retire;
    pipe_trace_t pipe_trace;
    word_t       halt_pc;               // byte address
    dbg_req_t    dbg_req;
    dbg_rsp_t    dbg_rsp;

    // Plusargs
    string       hex;
    string       trace_file;
    integer      trace_fd;              // 0: no trace
    string       mem_latency;           // +mem_latency
    logic        uncached;              // +uncached
    logic        irq_random;            // +irq_random given
    int unsigned irq_seed;              // its seed
    int unsigned irq_max_gap;           // +irq_max_gap
    word_t       irq_claim;             // address of irq_claim
    logic        meip;                  // the interrupt of TbMig3Irq
    wire  [MIG3_CFG.plic.sources:1] irq_src;   // the devices: TbMig3Irq is source 1
    wire         uart_tx;               // the UART's line out, into the console
    integer      uart_idle;             // clocks the line has been 1, up to a frame
    int          lat [6];               // its six numbers
    logic        expect_trap;
    logic        first_ebreak_traps;
    logic        expect_regs;
    logic        expect_mem_unchanged;
    logic        riscv_test;
    logic        no_debugger;
    string       symbols_file;          // +symbols: nm output of the program
    logic        check_halt_pc;
    word_t       expect_halt_pc;
    logic        check_exit;
    integer      expect_exit;
    integer      max_cycles;
    logic        check_pipeline;        // +max_pipeline_cycles given
    integer      max_pipeline_cycles;
    integer      pipeline_cycles;       // TbMig3BubbleCheck at the end
    integer      expect_retired;        // -1: not checked

    // State of the run
    integer      cycle;
    integer      retired;               // instructions retired (TbMig3RetireCheck)
    word_t       shadow [32];           // registers written by retire and the debugger
    logic [31:0] written;               // bit r: shadow[r] was written
    integer      traps;                 // retired instructions that trapped
    logic        ebreak_trapped;        // an EBREAK has trapped
    logic        ebreak_halt;           // EBREAK halts the core, else it traps (dbg_req)
    logic        halted;
    integer      resumes;               // halts after EBREAK left to resume
    logic        done;
    logic        exited;                // the program ended with a semihosting exit
    integer      exit_status;
    word_t       tohost;                // address of tohost, with +riscv_test
    logic        tohost_written;
    logic        mret_retired;          // an MRET retired (riscv-tests: the test body started)
    logic        tohost_in_body;        // tohost was written after an MRET
    word_t       tohost_value;

    SimClkGen #(.HALF_PERIOD(5)) u_sim_clk_gen(.clk);
    SimRstGen #(.CYCLES(3))      u_sim_rst_gen(.clk, .rst_n);

    assign irq_src = {{(MIG3_CFG.plic.sources - 1){1'b0}}, meip};
    Mig3Cpu u_mig3_cpu(.clk, .rst_n, .uncached, .irq_src, .uart_tx, .uart_rx(1'b1), .halt,
                       .retire, .pipe_trace, .dbg_req, .dbg_rsp);

    SimUartRx #(.CLKS_PER_BIT(UART_CLKS), .ECHO(1)) u_uart_console(.clk, .rst_n, .rx(uart_tx));

    always @(posedge clk)
        if (!rst_n || !uart_tx) uart_idle <= 0;
        else if (uart_idle < UART_FRAME) uart_idle <= uart_idle + 1;

    TbMig3PipeView u_pipe_view(.clk, .rst_n, .halt, .retire, .pipe_trace);

    TbMig3BubbleCheck u_bubble_check(
        .clk, .rst_n, .halt, .resume(dbg_req.resume), .retire, .cycle, .trace_fd);

    TbMig3Debugger u_debugger(.clk, .halt, .ebreak_halt, .cycle, .trace_fd, .dbg_rsp, .dbg_req);

    TbMig3Irq u_irq(
        .clk, .rst_n, .enable(irq_random), .seed(irq_seed), .max_gap(irq_max_gap),
        .claim_addr(irq_claim), .retire, .cycle, .trace_fd, .meip);

    TbMig3RetireCheck u_retire_check(
        .clk, .rst_n, .halt, .halted, .allow_trap(expect_trap || riscv_test), .retire, .dbg_req,
        .cycle, .trace_fd, .retired, .traps, .ebreak_trapped, .shadow, .written);

    assign halt_pc   = {dbg_rsp.halt_pc, {IADDR_START{1'b0}}};

    // Memories, symbols, checks at the end of the run

    // Word in the memory at byte address a, little-endian; the memory has AW address bits.
    function automatic insn_t imem_word(input logic [AW-1:0] a);
        for (int b = 0; b < 4; b++)
            imem_word[8*b +: 8] = u_mig3_cpu.u_mem.peek(a + b[AW-1:0]);
    endfunction

    // The image load() put into the memory, for +expect_mem_unchanged.
    logic [7:0] image [1 << AW];

    // Address of symbol `name` in file, the nm output of the program: lines of
    // address, type and name; lines without an address (undefined symbols) are skipped.
    task automatic find_symbol(input string file, input string name, output logic found,
                               output word_t addr);
        integer fd;
        string  line;
        // The type column is read only to get to the name.
        /* verilator lint_off UNUSEDSIGNAL */
        string  sym_type;
        /* verilator lint_on UNUSEDSIGNAL */
        string  sym_name;
        found = 1'b0;
        addr  = '0;
        fd = $fopen(file, "r");
        if (fd == 0)
            $fatal(1, "Mig3: can not open symbol file %s", file);
        while (!found && $fgets(line, fd) != 0)
            if ($sscanf(line, "%h %s %s", addr, sym_type, sym_name) == 3 && sym_name == name)
                found = 1'b1;
        $fclose(fd);
    endtask

    // +expect_mem_unchanged: every byte of the memory equals the byte of the image.
    task automatic check_mem_unchanged;
        logic [7:0] m;
        for (int a = 0; a < (1 << AW); a++) begin
            m = u_mig3_cpu.u_mem.peek(a[AW-1:0]);
            if (m !== image[a])
                $fatal(1, "Mig3: memory byte at %h is %h, image has %h", a[AW-1:0], m,
                       image[a]);
        end
    endtask

    // +expect_regs: compare the shadow registers with the table after the halting
    // instruction at halt_pc.
    task automatic check_regs;
        word_t a;
        word_t n;
        word_t r;
        word_t value;
        word_t got;
        a = halt_pc + 4;
        n = imem_word(a[AW-1:0]);
        if (n == 0 || n > 32)
            $fatal(1, "Mig3: +expect_regs: %0d entries at %h, no table after the halting instruction?",
                   n, a);
        repeat (n) begin
            a = a + 4;
            r = imem_word(a[AW-1:0]);
            a = a + 4;
            value = imem_word(a[AW-1:0]);
            if (r > 31)
                $fatal(1, "Mig3: +expect_regs: register %0d at %h", r, a - 4);
            if (r != 0 && !written[r[4:0]])
                $fatal(1, "Mig3: x%0d was never written, expected %h", r, value);
            got = (r == 0) ? '0 : shadow[r[4:0]];
            if (got !== value)
                $fatal(1, "Mig3: x%0d is %h, expected %h", r, got, value);
        end
    endtask

    // riscv-tests: the store to tohost, and whether the test body (entered with MRET) ran.
    always @(posedge clk)
        if (rst_n && retire.valid) begin
            if (retire.insn == MRET && !retire.trap)
                mret_retired <= 1'b1;
            if (riscv_test && !tohost_written && retire.mem_wmask != 0 &&
                retire.mem_addr == tohost) begin
                tohost_written <= 1'b1;
                tohost_value   <= retire.mem_wdata;
                tohost_in_body <= mret_retired;
            end
        end

    // The UART's characters still in its FIFO: wait until its line has been idle for a frame
    // (8 bytes in the FIFO at most), so that the console has printed them.
    task automatic uart_drain;
        for (int n = 0; uart_idle < UART_FRAME; n++) begin
            if (n > 10 * UART_FRAME)
                $fatal(1, "Mig3: the UART's line is not idle after %0d clocks", 10 * UART_FRAME);
            @(posedge clk); #1;
        end
    endtask

    // Run

    // Cycles of the run: every rising edge out of reset until the run is done.
    always @(posedge clk)
        if (rst_n && !done)
            cycle <= cycle + 1;

    initial begin
        // State of the run.
        cycle          = 0;
        done           = 1'b0;
        halted         = 1'b0;
        exited         = 1'b0;
        exit_status    = 0;
        tohost         = '0;
        tohost_written = 1'b0;
        mret_retired   = 1'b0;
        tohost_in_body = 1'b0;
        tohost_value   = '0;

        // Plusargs.
        expect_trap          = $test$plusargs("expect_trap");
        first_ebreak_traps   = $test$plusargs("first_ebreak_traps");
        expect_regs          = $test$plusargs("expect_regs");
        expect_mem_unchanged = $test$plusargs("expect_mem_unchanged");
        riscv_test           = $test$plusargs("riscv_test");
        no_debugger          = $test$plusargs("no_debugger");
        uncached             = $test$plusargs("uncached");
        irq_random           = $value$plusargs("irq_random=%d", irq_seed);
        if (!$value$plusargs("irq_max_gap=%d", irq_max_gap))     irq_max_gap    = 200;
        irq_claim            = '0;
        check_halt_pc        = $value$plusargs("expect_halt_pc=%h", expect_halt_pc);
        check_exit           = $value$plusargs("expect_exit=%d", expect_exit);
        if (!$value$plusargs("resumes=%d", resumes))               resumes        = 0;
        if (!$value$plusargs("max_cycles=%d", max_cycles))         max_cycles     = 100000;
        check_pipeline = $value$plusargs("max_pipeline_cycles=%d", max_pipeline_cycles);
        if (!$value$plusargs("expect_retired=%d", expect_retired)) expect_retired = -1;
        ebreak_halt = !first_ebreak_traps && !no_debugger;
        if ($value$plusargs("mem_latency=%s", mem_latency)) begin
            if ($sscanf(mem_latency, "%d,%d,%d,%d,%d,%d", lat[0], lat[1], lat[2], lat[3], lat[4],
                        lat[5]) != 6)
                $fatal(1, "Mig3: +mem_latency=%s: expected six numbers with commas",
                       mem_latency);
            u_mig3_cpu.u_mem.configure(lat[0], lat[1], lat[2], lat[3], lat[4], lat[5]);
        end

        // +trace=<file> writes the trace into <file>, +trace alone prints it.
        if ($value$plusargs("trace=%s", trace_file)) begin
            trace_fd = $fopen(trace_file, "w");
            if (trace_fd == 0)
                $fatal(1, "Mig3: can not open trace file %s", trace_file);
            $display("Mig3: trace in %s", trace_file);
        end else if ($test$plusargs("trace"))
            trace_fd = 32'h8000_0001;   // stdout
        else
            trace_fd = 0;

        if (!$value$plusargs("hex=%s", hex))
            $fatal(1, "Mig3: plusarg +hex=<file> is missing");
        $readmemh(hex, image);
        if (u_mig3_cpu.load(hex) != 1)
            $fatal(1, "Mig3: load() of %s returned 0", hex);
        if (riscv_test) begin
            logic found;
            if (!$value$plusargs("symbols=%s", symbols_file))
                $fatal(1, "Mig3: +riscv_test needs +symbols=<file>");
            find_symbol(symbols_file, "tohost", found, tohost);
            if (!found)
                $fatal(1, "Mig3: no symbol tohost in %s", symbols_file);
        end
        if (irq_random) begin
            logic found;
            if (!$value$plusargs("symbols=%s", symbols_file))
                $fatal(1, "Mig3: +irq_random needs +symbols=<file>");
            find_symbol(symbols_file, "irq_claim", found, irq_claim);
            if (!found)
                $fatal(1, "Mig3: +irq_random: no symbol irq_claim in %s", symbols_file);
        end

        @(posedge rst_n);
        while (!done) begin
            while (!halt && !tohost_written) begin
                @(posedge clk); #1;
                if (cycle > max_cycles)
                    $fatal(1, "Mig3: no end after %0d cycles (+max_cycles), %0d instructions retired",
                           max_cycles, retired);
                if (ebreak_trapped && !no_debugger)
                    ebreak_halt = 1'b1;
            end
            if (tohost_written)
                done = 1'b1;    // riscv-tests: the environment loops, the core runs on
            else if (u_debugger.semihost_call(halt_pc)) begin
                halted = 1'b1;
                uart_drain();   // what the program printed on the UART comes first
                u_debugger.semihost(exited, exit_status);
                done   = exited;
                halted = exited;
            end else if (resumes == 0) begin
                halted = 1'b1;
                done   = 1'b1;
            end else begin
                halted = 1'b1;
                u_debugger.debug_and_resume(written[RiscvPkg::REG_A0],
                                            shadow[RiscvPkg::REG_A0]);
                resumes = resumes - 1;
                halted  = 1'b0;
            end
        end
        @(posedge clk); #1;         // the always block has seen the last retire
        uart_drain();
        if (u_uart_console.framing_errors != 0)
            $fatal(1, "Mig3: %0d framing errors on the UART's line (another rate than %0d clocks a bit?)",
                   u_uart_console.framing_errors, UART_CLKS);
        if (expect_trap && traps == 0)
            $fatal(1, "Mig3: +expect_trap, but no instruction trapped");
        if (check_exit && !exited)
            $fatal(1, "Mig3: no semihosting exit, halted at %h", halt_pc);
        if (exited && exit_status != (check_exit ? expect_exit : 0))
            $fatal(1, "Mig3: semihosting exit %0d, expected %0d",
                   exit_status, check_exit ? expect_exit : 0);

        if (!tohost_written) begin
            repeat (5) @(posedge clk);  // nothing may retire after halt
            if (!halt)
                $fatal(1, "Mig3: core runs again after the halt at %h", halt_pc);
        end
        if (expect_retired >= 0 && retired != expect_retired)
            $fatal(1, "Mig3: %0d instructions retired, expected %0d", retired, expect_retired);
        if (check_halt_pc && halt_pc !== expect_halt_pc)
            $fatal(1, "Mig3: halted at %h, expected %h", halt_pc, expect_halt_pc);
        if (expect_regs)
            check_regs();
        if (expect_mem_unchanged)
            check_mem_unchanged();
        if (riscv_test && !tohost_written)
            $fatal(1, "Mig3: riscv-tests: no store to tohost (%h), halted at %h", tohost, halt_pc);
        if (riscv_test && !tohost_in_body)
            $fatal(1, "Mig3: riscv-tests: tohost=%h before the test body (no MRET of the environment)",
                   tohost_value);
        u_bubble_check.report(pipeline_cycles);
        // @kb: test/design/mig2/pipeline_cycles
        if (check_pipeline && pipeline_cycles > max_pipeline_cycles)
            $fatal(1, "Mig3: %0d pipeline cycles, above the ceiling %0d (+max_pipeline_cycles)",
                   pipeline_cycles, max_pipeline_cycles);
        if (riscv_test && tohost_value != 1)
            $fatal(1, "Mig3: riscv-tests: case %0d failed (tohost=%h)",
                   tohost_value >> 1, tohost_value);
        if (tohost_written)
            $display("PASS: %0d instructions retired in %0d cycles, tohost=%h",
                     retired, cycle, tohost_value);
        else
            $display("PASS: %0d instructions retired in %0d cycles, halted at %h",
                     retired, cycle, halt_pc);
        if (trace_file.len() != 0)
            $fclose(trace_fd);
        $finish;
    end
endmodule

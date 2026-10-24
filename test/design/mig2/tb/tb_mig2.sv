/* Testbench of Mig2Cpu running a program.
 *
 * Loads +hex=<file>, releases reset and runs until the core halts.
 * retire is the RVFI trace of the core (see Mig2Pkg). Checks of every retired instruction:
 * - retire.insn is the imem word at pc_rdata: fetch gets the right instruction,
 * - the first retired pc is the reset address, order counts 0, 1, 2, ...,
 * - pc_rdata is pc_wdata of the previous retired instruction (control flow),
 * - rs1_rdata, rs2_rdata are the shadow registers (registers read), 0 for x0,
 * - load or store: mem_addr and the mask are the access of the instruction:
 *   address rs1_rdata + imm, size by funct3 (computed here from insn),
 * - load: bytes of mem_rdata under mem_rmask are the bytes of dmem,
 * - store: when it retires, dmem has the bytes of mem_wdata under mem_wmask (the store
 *   wrote one cycle before, in EX; a younger store writes at the end of the retire cycle),
 * - traps only with +expect_trap,
 * - nothing retires after halt,
 * - no X or Z in retire (Icarus only, Verilator is 2-state),
 * - with +expect_sequential: every pc is the previous pc + 4 (straight-line code).
 * Register writes of retire (rd_addr, rd_wdata) are kept in a shadow copy of the registers.
 * The testbench is the debugger: dbg_req.ebreak_halt=1, so EBREAK halts the core
 * (with +first_ebreak_traps it is 0 until an EBREAK has trapped, then 1).
 * At the end the core must be halted, and
 * - with +expect_trap: at least one trap happened,
 * - with +expect_retired=<n>: n instructions retired,
 * - with +expect_halt_pc=<hex byte address without 0x>: the core halted there,
 * - with +expect_regs: the shadow registers have the values of the table that the
 *   program puts right after the halting EBREAK: number of entries n, then n pairs of
 *   words register, value; a register in the table that was never written fails,
 * - with +expect_mem_unchanged: dmem equals imem byte for byte; Mig2Cpu loads the
 *   same image into both, so this shows that nothing was stored,
 * - with +riscv_test: the program is a riscv-tests test with its standard environment
 *   (env/p). It ends with a store to the word tohost, address from +symbols=<file> (nm
 *   output of the program): 1 is pass, (case << 1) | 1 is case `case` failed. The run
 *   ends at that store, the core does not halt (the environment loops). Traps are
 *   allowed: the environment probes CSRs Mig2 does not have, and an unexpected trap
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
 * The debug port and the semihosting calls: TbMig2Debugger.
 * Other plusargs: +trace=<file> writes every retired instruction, register write,
 * debug action and semihosting call into <file>, +trace alone prints them;
 * +max_cycles=<n> (default 100000).
 * Bubbles, their checks, their trace lines and the count per reason at the end:
 * TbMig2BubbleCheck.
 * Pipeline view, checked against pipe_trace, and its Konata log (+kanata=<file>):
 * TbMig2PipeView.
 * Stops at the first failure with $fatal.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module TbMig2;
    import Mig2Pkg::*;
    import RiscvPkg::*;
    import RiscvInstrPkg::*;

    localparam AW = MIG2_CFG.mem_addr_width;

    logic        clk;
    logic        rst_n;
    logic        halt;
    retire_t     retire;
    pipe_trace_t pipe_trace;
    word_t       retire_pc;             // byte address
    word_t       halt_pc;               // byte address
    dbg_req_t    dbg_req;
    dbg_rsp_t    dbg_rsp;

    // Plusargs
    string       hex;
    string       trace_file;
    integer      trace_fd;              // 0: no trace
    logic        expect_sequential;
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
    integer      expect_retired;        // -1: not checked

    // State of the run
    integer      cycle;
    integer      retired;
    word_t       prev_pc;
    word_t       prev_pc_wdata;         // next pc told by the previous retired instruction
    word_t       shadow [32];           // registers written by retired instructions
    logic [31:0] written;               // bit r: shadow[r] was written
    integer      traps;
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

    // Access that the load or store in retire must make
    word_t       access_addr;           // byte address
    strb_t       access_mask;           // its bytes

    SimClkGen #(.HALF_PERIOD(5)) u_sim_clk_gen(.clk);
    SimRstGen #(.CYCLES(3))      u_sim_rst_gen(.clk, .rst_n);

    Mig2Cpu u_mig2_cpu(.clk, .rst_n, .halt, .retire, .pipe_trace, .dbg_req, .dbg_rsp);

    TbMig2PipeView u_pipe_view(.clk, .rst_n, .halt, .retire, .pipe_trace);

    TbMig2BubbleCheck u_bubble_check(
        .clk, .rst_n, .halt, .resume(dbg_req.resume), .retire, .cycle, .trace_fd);

    TbMig2Debugger u_debugger(.clk, .halt, .ebreak_halt, .cycle, .trace_fd, .dbg_rsp, .dbg_req);

    assign retire_pc = retire.pc_rdata;
    assign halt_pc   = {dbg_rsp.halt_pc, {IADDR_START{1'b0}}};

    // Memories, symbols, checks at the end of the run

    // Instruction in imem at byte address a, little-endian; imem has AW address bits.
    function automatic insn_t imem_word(input logic [AW-1:0] a);
        for (int b = 0; b < 4; b++)
            imem_word[8*b +: 8] = u_mig2_cpu.u_imem.peek(a + b[AW-1:0]);
    endfunction

    // Byte and word (little-endian) of dmem at byte address a. Memories wrap around:
    // only the AW low bits of an address are used.
    /* verilator lint_off UNUSEDSIGNAL */
    function automatic logic [7:0] dmem_byte(input word_t a);
        return u_mig2_cpu.u_dmem.peek(a[AW-1:0]);
    endfunction
    /* verilator lint_on UNUSEDSIGNAL */

    function automatic word_t dmem_word(input word_t a);
        word_t ab;
        for (int b = 0; b < 4; b++) begin
            ab = a + b;
            dmem_word[8*b +: 8] = dmem_byte(ab);
        end
    endfunction

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
            $fatal(1, "Mig2: can not open symbol file %s", file);
        while (!found && $fgets(line, fd) != 0)
            if ($sscanf(line, "%h %s %s", addr, sym_type, sym_name) == 3 && sym_name == name)
                found = 1'b1;
        $fclose(fd);
    endtask

    // +expect_mem_unchanged: every byte of dmem equals the byte of imem.
    task automatic check_mem_unchanged;
        logic [7:0] i;
        logic [7:0] d;
        for (int a = 0; a < (1 << AW); a++) begin
            i = u_mig2_cpu.u_imem.peek(a[AW-1:0]);
            d = u_mig2_cpu.u_dmem.peek(a[AW-1:0]);
            if (d !== i)
                $fatal(1, "Mig2: dmem byte at %h is %h, image has %h", a[AW-1:0], d, i);
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
            $fatal(1, "Mig2: +expect_regs: %0d entries at %h, no table after the halting instruction?",
                   n, a);
        repeat (n) begin
            a = a + 4;
            r = imem_word(a[AW-1:0]);
            a = a + 4;
            value = imem_word(a[AW-1:0]);
            if (r > 31)
                $fatal(1, "Mig2: +expect_regs: register %0d at %h", r, a - 4);
            if (r != 0 && !written[r[4:0]])
                $fatal(1, "Mig2: x%0d was never written, expected %h", r, value);
            got = (r == 0) ? '0 : shadow[r[4:0]];
            if (got !== value)
                $fatal(1, "Mig2: x%0d is %h, expected %h", r, got, value);
        end
    endtask

    // Access that the load or store in retire must make

    typedef enum logic [1:0] {
        MEM_NONE,
        MEM_LOAD,
        MEM_STORE
    } mem_kind_e;

    // Kind of memory access of insn.
    function automatic mem_kind_e mem_kind(input insn_t insn);
        casez (insn)
            LB, LH, LW, LBU, LHU: return MEM_LOAD;
            SB, SH, SW:           return MEM_STORE;
            default:              return MEM_NONE;
        endcase
    endfunction

    // Byte address of the load or store insn when rs1 is base: base + S or I immediate.
    function automatic word_t mem_byte_addr(input insn_t insn, input word_t base);
        return base + (mem_kind(insn) == MEM_STORE ? imm_s_of(insn) : imm_i_of(insn));
    endfunction

    // Bytes of the access of insn at byte offset `offset` in the word: size by funct3.
    function automatic strb_t mem_mask(input insn_t insn, input byte_offset_t offset);
        insn_fmt_t f;
        strb_t     size;
        f.word = insn;
        case (f.i.funct3)
            F3_B, F3_BU: size = 4'b0001;
            F3_H, F3_HU: size = 4'b0011;
            default:     size = 4'b1111;
        endcase
        return size << offset;
    endfunction

    assign access_addr = mem_byte_addr(retire.insn, retire.rs1_rdata);
    assign access_mask = mem_mask(retire.insn, access_addr[DADDR_START-1:0]);

    // Bytes of data under mask are the bytes of dmem in the word at a.
    function automatic logic dmem_has(input word_t a, input strb_t mask, input word_t data);
        word_t ab;
        for (int b = 0; b < STRB_WIDTH; b++) begin
            ab = a + b;
            if (mask[b] && dmem_byte(ab) !== data[8*b +: 8])
                return 1'b0;
        end
        return 1'b1;
    endfunction

    // Checks of every retired instruction

    // Register r read by the instruction in retire gave data: the shadow value, 0 for x0
    // and for an unused register (r = 0).
    task automatic check_read(input reg_id_t r, input word_t data);
        if (r == 0 && data !== '0)
            $fatal(1, "Mig2: pc %h read data of x0 or of an unused register is not 0", retire_pc);
        if (r != 0 && written[r] && data !== shadow[r])
            $fatal(1, "Mig2: pc %h read x%0d = %h, expected %h", retire_pc, r, data, shadow[r]);
    endtask

    // Load or store in retire that did not trap: its address and mask are access_addr
    // and access_mask, the mask of the other direction is 0.
    task automatic check_access;
        logic  load;
        word_t word_addr;     // access_addr, word aligned
        strb_t mask;          // mem_rmask of a load, mem_wmask of a store
        strb_t other_mask;    // the other one
        load       = mem_kind(retire.insn) == MEM_LOAD;
        word_addr  = {access_addr[WIDTH-1:DADDR_START], {DADDR_START{1'b0}}};
        mask       = load ? retire.mem_rmask : retire.mem_wmask;
        other_mask = load ? retire.mem_wmask : retire.mem_rmask;
        if (retire.mem_addr !== word_addr || mask !== access_mask || other_mask !== '0)
            $fatal(1, "Mig2: pc %h accesses mem[%h] r %b w %b, expected address %h mask %b",
                   retire_pc, retire.mem_addr, retire.mem_rmask, retire.mem_wmask,
                   access_addr, access_mask);
    endtask

    // Values of the cycle before the rising edge; also the register writes of the debugger.
    always @(posedge clk) begin
        if (rst_n && retire.valid) begin
`ifndef VERILATOR
            if ($isunknown(retire))
                $fatal(1, "Mig2: X or Z in retire: %h", retire);
`endif
            if (halted)
                $fatal(1, "Mig2: instruction at %h retired after halt", retire_pc);
            if (retired == 0 && retire_pc !== MIG2_CFG.rst_addr)
                $fatal(1, "Mig2: first instruction at %h, expected reset address %h",
                       retire_pc, MIG2_CFG.rst_addr);
            if (expect_sequential && retired > 0 && retire_pc !== prev_pc + 4)
                $fatal(1, "Mig2: pc %h after %h, expected %h", retire_pc, prev_pc, prev_pc + 4);
            if (retire.insn !== imem_word(retire_pc[AW-1:0]))
                $fatal(1, "Mig2: insn %h at pc %h, imem has %h",
                       retire.insn, retire_pc, imem_word(retire_pc[AW-1:0]));
            if (retire.order !== {32'b0, retired})
                $fatal(1, "Mig2: order %0d at pc %h, expected %0d",
                       retire.order, retire_pc, retired);
            if (retired > 0 && retire_pc !== prev_pc_wdata)
                $fatal(1, "Mig2: pc %h, the instruction before (at %h) gave next pc %h",
                       retire_pc, prev_pc, prev_pc_wdata);
            check_read(retire.rs1_addr, retire.rs1_rdata);
            check_read(retire.rs2_addr, retire.rs2_rdata);
            if (mem_kind(retire.insn) != MEM_NONE && !retire.trap)
                check_access();
            else if (retire.mem_rmask != 0 || retire.mem_wmask != 0)
                $fatal(1, "Mig2: pc %h is not a load or store (or trapped), but has a memory access",
                       retire_pc);
            if (retire.mem_rmask != 0 &&
                !dmem_has(retire.mem_addr, retire.mem_rmask, retire.mem_rdata))
                $fatal(1, "Mig2: load at pc %h from %h mask %b got %h, dmem has %h",
                       retire_pc, retire.mem_addr, retire.mem_rmask, retire.mem_rdata,
                       dmem_word(retire.mem_addr));
            if (retire.mem_wmask != 0 &&
                !dmem_has(retire.mem_addr, retire.mem_wmask, retire.mem_wdata))
                $fatal(1, "Mig2: store at %h to %h mask %b data %h: dmem has %h",
                       retire_pc, retire.mem_addr, retire.mem_wmask, retire.mem_wdata,
                       dmem_word(retire.mem_addr));
            if (retire.trap && !expect_trap && !riscv_test)
                $fatal(1, "Mig2: trap at pc %h", retire_pc);
            if (retire.insn == MRET && !retire.trap)
                mret_retired <= 1'b1;
            if (riscv_test && !tohost_written && retire.mem_wmask != 0 &&
                retire.mem_addr == tohost) begin
                tohost_written <= 1'b1;
                tohost_value   <= retire.mem_wdata;
                tohost_in_body <= mret_retired;
            end
            if (retire.trap) begin
                traps <= traps + 1;
                if (retire.insn == INSN_EBREAK)
                    ebreak_trapped <= 1'b1;
            end
            if (trace_fd != 0) begin
                $fwrite(trace_fd, "%8d pc=%h insn=%h", cycle, retire_pc, retire.insn);
                if (retire.rd_addr != 0)
                    $fwrite(trace_fd, " x%0d <= %h", retire.rd_addr, retire.rd_wdata);
                if (retire.mem_rmask != 0)
                    $fwrite(trace_fd, " mem[%h] r %h mask %b",
                            retire.mem_addr, retire.mem_rdata, retire.mem_rmask);
                if (retire.mem_wmask != 0)
                    $fwrite(trace_fd, " mem[%h] w %h mask %b",
                            retire.mem_addr, retire.mem_wdata, retire.mem_wmask);
                if (retire.trap)
                    $fwrite(trace_fd, " trap");
                $fwrite(trace_fd, "\n");
            end
            if (retire.rd_addr != 0) begin
                shadow[retire.rd_addr]  <= retire.rd_wdata;
                written[retire.rd_addr] <= 1'b1;
            end
            prev_pc       <= retire_pc;
            prev_pc_wdata <= retire.pc_wdata;
            retired       <= retired + 1;
        end
        if (halt && dbg_req.reg_wr && dbg_req.reg_id != 0) begin
            if (trace_fd != 0)
                $fdisplay(trace_fd, "%8d debug x%0d <= %h",
                          cycle, dbg_req.reg_id, dbg_req.reg_wdata);
            shadow[dbg_req.reg_id]  <= dbg_req.reg_wdata;
            written[dbg_req.reg_id] <= 1'b1;
        end else if (halt && dbg_req.resume && trace_fd != 0)
            $fdisplay(trace_fd, "%8d resume", cycle);
    end

    // Run

    // Cycles of the run: every rising edge out of reset until the run is done.
    always @(posedge clk)
        if (rst_n && !done)
            cycle <= cycle + 1;

    initial begin
        // State of the run.
        cycle          = 0;
        done           = 1'b0;
        retired        = 0;
        prev_pc        = '0;
        prev_pc_wdata  = '0;
        written        = '0;
        traps          = 0;
        ebreak_trapped = 1'b0;
        halted         = 1'b0;
        exited         = 1'b0;
        exit_status    = 0;
        tohost         = '0;
        tohost_written = 1'b0;
        mret_retired   = 1'b0;
        tohost_in_body = 1'b0;
        tohost_value   = '0;

        // Plusargs.
        expect_sequential    = $test$plusargs("expect_sequential");
        expect_trap          = $test$plusargs("expect_trap");
        first_ebreak_traps   = $test$plusargs("first_ebreak_traps");
        expect_regs          = $test$plusargs("expect_regs");
        expect_mem_unchanged = $test$plusargs("expect_mem_unchanged");
        riscv_test           = $test$plusargs("riscv_test");
        no_debugger          = $test$plusargs("no_debugger");
        check_halt_pc        = $value$plusargs("expect_halt_pc=%h", expect_halt_pc);
        check_exit           = $value$plusargs("expect_exit=%d", expect_exit);
        if (!$value$plusargs("resumes=%d", resumes))               resumes        = 0;
        if (!$value$plusargs("max_cycles=%d", max_cycles))         max_cycles     = 100000;
        if (!$value$plusargs("expect_retired=%d", expect_retired)) expect_retired = -1;
        ebreak_halt = !first_ebreak_traps && !no_debugger;

        // +trace=<file> writes the trace into <file>, +trace alone prints it.
        if ($value$plusargs("trace=%s", trace_file)) begin
            trace_fd = $fopen(trace_file, "w");
            if (trace_fd == 0)
                $fatal(1, "Mig2: can not open trace file %s", trace_file);
            $display("Mig2: trace in %s", trace_file);
        end else if ($test$plusargs("trace"))
            trace_fd = 32'h8000_0001;   // stdout
        else
            trace_fd = 0;

        if (!$value$plusargs("hex=%s", hex))
            $fatal(1, "Mig2: plusarg +hex=<file> is missing");
        if (u_mig2_cpu.load(hex) != 1)
            $fatal(1, "Mig2: load() of %s returned 0", hex);
        if (riscv_test) begin
            logic found;
            if (!$value$plusargs("symbols=%s", symbols_file))
                $fatal(1, "Mig2: +riscv_test needs +symbols=<file>");
            find_symbol(symbols_file, "tohost", found, tohost);
            if (!found)
                $fatal(1, "Mig2: no symbol tohost in %s", symbols_file);
        end

        @(posedge rst_n);
        while (!done) begin
            while (!halt && !tohost_written) begin
                @(posedge clk); #1;
                if (cycle > max_cycles)
                    $fatal(1, "Mig2: no halt after %0d cycles, %0d instructions retired",
                           max_cycles, retired);
                if (ebreak_trapped && !no_debugger)
                    ebreak_halt = 1'b1;
            end
            if (tohost_written)
                done = 1'b1;    // riscv-tests: the environment loops, the core runs on
            else if (u_debugger.semihost_call(halt_pc)) begin
                halted = 1'b1;
                u_debugger.semihost(exited, exit_status);
                done   = exited;
                halted = exited;
            end else if (resumes == 0) begin
                halted = 1'b1;
                done   = 1'b1;
            end else begin
                halted = 1'b1;
                u_debugger.debug_and_resume(written[10], shadow[10]);
                resumes = resumes - 1;
                halted  = 1'b0;
            end
        end
        @(posedge clk); #1;         // the always block has seen the last retire
        if (expect_trap && traps == 0)
            $fatal(1, "Mig2: +expect_trap, but no instruction trapped");
        if (check_exit && !exited)
            $fatal(1, "Mig2: no semihosting exit, halted at %h", halt_pc);
        if (exited && exit_status != (check_exit ? expect_exit : 0))
            $fatal(1, "Mig2: semihosting exit %0d, expected %0d",
                   exit_status, check_exit ? expect_exit : 0);

        if (!tohost_written) begin
            repeat (5) @(posedge clk);  // nothing may retire after halt
            if (!halt)
                $fatal(1, "Mig2: core runs again after the halt at %h", halt_pc);
        end
        if (expect_retired >= 0 && retired != expect_retired)
            $fatal(1, "Mig2: %0d instructions retired, expected %0d", retired, expect_retired);
        if (check_halt_pc && halt_pc !== expect_halt_pc)
            $fatal(1, "Mig2: halted at %h, expected %h", halt_pc, expect_halt_pc);
        if (expect_regs)
            check_regs();
        if (expect_mem_unchanged)
            check_mem_unchanged();
        if (riscv_test && !tohost_written)
            $fatal(1, "Mig2: riscv-tests: no store to tohost (%h), halted at %h", tohost, halt_pc);
        if (riscv_test && !tohost_in_body)
            $fatal(1, "Mig2: riscv-tests: tohost=%h before the test body (no MRET of the environment)",
                   tohost_value);
        u_bubble_check.report();
        if (riscv_test && tohost_value != 1)
            $fatal(1, "Mig2: riscv-tests: case %0d failed (tohost=%h)",
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

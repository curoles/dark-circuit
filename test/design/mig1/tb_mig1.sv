/* Testbench of Mig1Cpu running a program.
 *
 * Loads +hex=<file>, releases reset and runs until the core halts.
 * retire is the RVFI trace of the core (see Mig1Pkg). Checks of every retired instruction:
 * - retire.insn is the imem word at pc_rdata: fetch gets the right instruction,
 * - the first retired pc is the reset address, order counts 0, 1, 2, ...,
 * - pc_rdata is pc_wdata of the previous retired instruction (control flow),
 * - rs1_rdata, rs2_rdata are the shadow registers (registers read), 0 for x0,
 * - load or store: mem_addr and the mask are the access of the instruction:
 *   address rs1_rdata + imm, size by funct3 (computed here from insn),
 * - load: bytes of mem_rdata under mem_rmask are the bytes of dmem,
 * - store: one clock later dmem has the bytes of mem_wdata under mem_wmask,
 * - trap only with +expect_illegal, as the last instruction, at halt_pc,
 * - nothing retires after halt,
 * - no X or Z in retire (Icarus only, Verilator is 2-state),
 * - with +expect_sequential: every pc is the previous pc + 4 (straight-line code).
 * Register writes of retire (rd_addr, rd_wdata) are kept in a shadow copy of the registers.
 * At the end: halt with illegal=0 passes, illegal=1 fails; with +expect_illegal it is
 * the other way around, and a resume must not restart the core (illegal=1 is final). And
 * - with +expect_retired=<n>: n instructions retired,
 * - with +expect_halt_pc=<hex byte address without 0x>: the core halted there,
 * - with +expect_regs: the shadow registers have the values of the table that the
 *   program puts right after the halting instruction (EBREAK, or the instruction
 *   that made illegal=1): number of entries n, then n pairs of
 *   words register, value; a register in the table that was never written fails,
 * - with +expect_mem_unchanged: dmem equals imem byte for byte; Mig1Cpu loads the
 *   same image into both, so this shows that nothing was stored,
 * - with +riscv_test: a0, read through the debug port, is 0: a riscv-tests test
 *   passed; else a0 is (case << 1) | 1 of the failed case, see riscv_test.h.
 * With +resumes=<n> the testbench is a debugger at the first n halts after EBREAK:
 * it reads a0 (x10) through the debug port (must equal the shadow), writes
 * a0 + 0x100, and resumes the core; the halt after that ends the run. The shadow registers
 * follow debug writes too.
 * Semihosting: an EBREAK between slli x0,x0,0x1f and srai x0,x0,7 is a semihosting
 * call (RISC-V semihosting spec). The testbench reads the operation (a0) and its
 * argument (a1) through the debug port, argument blocks and strings from dmem with
 * peek(), does it and resumes the core; these halts do not count for +resumes.
 * SYS_WRITEC and SYS_WRITE0 print to stdout; SYS_EXIT and SYS_EXIT_EXTENDED end the
 * run with an exit status. With +expect_exit=<n> the program must end with status n,
 * without it a semihosting exit must have status 0. Other operations fail.
 * Other plusargs: +trace=<file> writes every retired instruction, register write,
 * debug action and semihosting call into <file>, +trace alone prints them;
 * +max_cycles=<n> (default 100000).
 * Stops at the first failure with $fatal.
 */
module TbMig1;
    import Mig1Pkg::*;
    import RiscvPkg::*;
    import RiscvInstrPkg::*;

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
    reg              riscv_test;
    reg [WIDTH-1:0]  shadow [32];   // registers written by retired instructions
    reg [31:0]       written;       // bit r: shadow[r] was written
    integer          cycle;
    integer          retired;
    reg [WIDTH-1:0]  prev_pc;
    reg [WIDTH-1:0]  prev_pc_wdata;  // next pc told by the previous retired instruction
    reg              last_trap;      // the last retired instruction trapped
    reg              store_check;    // check dmem for the store retired one clock before
    reg [WIDTH-1:0]  store_addr;
    strb_t           store_mask;
    reg [WIDTH-1:0]  store_data;
    wire [WIDTH-1:0] access_addr;    // byte address of the load or store in retire
    strb_t           access_mask;    // its bytes
    reg              halted;
    integer          resumes;       // halts after EBREAK left to resume
    reg              done;
    reg              check_exit;
    integer          expect_exit;
    reg              exited;        // the program ended with a semihosting exit
    integer          exit_status;

    SimClkGen #(.HALF_PERIOD(5)) u_sim_clk_gen(.clk(clk));
    SimRstGen #(.CYCLES(3))      u_sim_rst_gen(.clk(clk), .rst_n(rst_n));

    Mig1Cpu u_mig1_cpu(.clk(clk), .rst_n(rst_n), .halt(halt), .illegal(illegal), .retire(retire),
                       .dbg_req(dbg_req), .dbg_rsp(dbg_rsp));

    assign retire_pc = retire.pc_rdata;
    assign halt_pc   = {dbg_rsp.halt_pc, {IADDR_START{1'b0}}};

    // Word of imem at byte address a, little-endian; imem has AW address bits.
    function automatic [31:0] imem_word(input [AW-1:0] a);
        for (int b = 0; b < 4; b++)
            imem_word[8*b +: 8] = u_mig1_cpu.u_imem.peek(a + b[AW-1:0]);
    endfunction

    // +riscv_test: result of a riscv-tests test in a0, read through the debug port.
    task automatic check_riscv_test;
        logic [WIDTH-1:0] a0;
        dbg_req.reg_addr = 10;
        #1;
        a0 = dbg_rsp.reg_rdata;
        if (a0 !== '0)
            $fatal(1, "Mig1: riscv-tests: case %0d failed (a0=%h)", a0 >> 1, a0);
    endtask

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

    // Value of register r, read through the debug port while halted.
    task automatic dbg_read(input logic [REG_ADDR_WIDTH-1:0] r, output logic [WIDTH-1:0] value);
        dbg_req.reg_addr = r;
        #1;
        value = dbg_rsp.reg_rdata;
    endtask

    // resume=1 for one clock; with must_run=1 the core must run after it.
    task automatic resume_core(input logic must_run);
        dbg_req.resume = 1'b1;
        @(posedge clk); #1;
        cycle = cycle + 1;
        dbg_req.resume = 1'b0;
        if (must_run && halt)
            $fatal(1, "Mig1: resume at %h, the core is still halted", halt_pc);
    endtask

    // Byte and word (little-endian) of dmem at byte address a. Memories wrap around:
    // only the AW low bits of an address are used.
    /* verilator lint_off UNUSEDSIGNAL */
    function automatic [7:0] dmem_byte(input [WIDTH-1:0] a);
        return u_mig1_cpu.u_dmem.peek(a[AW-1:0]);
    endfunction
    /* verilator lint_on UNUSEDSIGNAL */

    function automatic [31:0] dmem_word(input [WIDTH-1:0] a);
        logic [WIDTH-1:0] ab;
        for (int b = 0; b < 4; b++) begin
            ab = a + b;
            dmem_word[8*b +: 8] = dmem_byte(ab);
        end
    endfunction

    // Semihosting call at halt_pc: EBREAK between the entry and the exit no-op.
    localparam [31:0] SEMIHOST_ENTRY = 32'h01f01013;    // slli x0, x0, 0x1f
    localparam [31:0] SEMIHOST_NOP   = 32'h40705013;    // srai x0, x0, 7
    localparam [31:0] ADP_STOPPED_APPLICATION_EXIT = 32'h20026;

    function automatic logic semihost_call;
        // Only the AW low bits of the addresses are used, see dmem_byte.
        /* verilator lint_off UNUSEDSIGNAL */
        logic [WIDTH-1:0] prev_addr;   // address of the instruction before the EBREAK
        logic [WIDTH-1:0] next_addr;   // and after it
        /* verilator lint_on UNUSEDSIGNAL */
        prev_addr = halt_pc - 4;
        next_addr = halt_pc + 4;
        return imem_word(halt_pc[AW-1:0]) === INSN_EBREAK &&
               imem_word(prev_addr[AW-1:0]) === SEMIHOST_ENTRY &&
               imem_word(next_addr[AW-1:0]) === SEMIHOST_NOP;
    endfunction

    // Do the semihosting call at halt_pc; resume the core unless it is an exit.
    task automatic semihost;
        logic [WIDTH-1:0] op;
        logic [WIDTH-1:0] arg;
        logic [WIDTH-1:0] a;
        logic [WIDTH-1:0] reason;
        dbg_read(10, op);
        dbg_read(11, arg);
        if (trace_fd != 0)
            $fdisplay(trace_fd, "%8d semihost op %h arg %h", cycle, op, arg);
        case (op)
            32'h03:     // SYS_WRITEC: byte at arg
                $write("%c", dmem_byte(arg));
            32'h04: begin   // SYS_WRITE0: string at arg
                a = arg;
                while (dmem_byte(a) != 0) begin
                    $write("%c", dmem_byte(a));
                    a = a + 1;
                end
            end
            32'h18: begin   // SYS_EXIT: on RV32 arg is the reason, no status
                exited      = 1;
                exit_status = (arg == ADP_STOPPED_APPLICATION_EXIT) ? 0 : 1;
            end
            32'h20: begin   // SYS_EXIT_EXTENDED: block {reason, status}
                a = arg + 4;
                reason      = dmem_word(arg);
                exited      = 1;
                exit_status = (reason == ADP_STOPPED_APPLICATION_EXIT) ? dmem_word(a) : 1;
            end
            default:
                $fatal(1, "Mig1: semihosting operation %h at %h is not supported", op, halt_pc);
        endcase
        if (exited) begin
            $display("Mig1: semihosting exit %0d", exit_status);
            if (trace_fd != 0)
                $fdisplay(trace_fd, "%8d semihost exit %0d", cycle, exit_status);
        end else
            resume_core(1'b1);
    endtask

    // Debugger at a halt after EBREAK: read a0, write a0 + 0x100, resume. One clock
    // each for the write and the resume; the shadow follows the write in the always
    // block. Not a0 + 1: that is what the EBREAK in EX computes (rs1 + imm, rs1 is
    // read port 0 = x10), so a debug write that is lost would not be noticed.
    task automatic debug_and_resume;
        logic [WIDTH-1:0] a0;
        if (imem_word(halt_pc[AW-1:0]) !== INSN_EBREAK)
            $fatal(1, "Mig1: halted at %h, it is not EBREAK", halt_pc);
        dbg_read(10, a0);
        if (written[10] && a0 !== shadow[10])
            $fatal(1, "Mig1: debug read of x10 gave %h, expected %h", a0, shadow[10]);
        dbg_req.reg_wdata = a0 + 32'h100;
        dbg_req.reg_wr    = 1'b1;
        @(posedge clk); #1;
        cycle = cycle + 1;
        dbg_req.reg_wr    = 1'b0;
        resume_core(1'b1);
    endtask

    // Kind of memory access of insn: 1 load, 2 store, 0 none.
    function automatic logic [1:0] mem_kind(input [31:0] insn);
        casez (insn)
            LB, LH, LW, LBU, LHU: return 2'd1;
            SB, SH, SW:           return 2'd2;
            default:              return 2'd0;
        endcase
    endfunction

    // Byte address of the load or store insn when rs1 is base: base + I or S immediate.
    function automatic [WIDTH-1:0] mem_byte_addr(input [31:0] insn, input [WIDTH-1:0] base);
        insn_fmt_t f;
        f.word = insn;
        if (mem_kind(insn) == 2'd2)
            return base + {{(WIDTH-12){f.s.imm_11_5[6]}}, f.s.imm_11_5, f.s.imm_4_0};
        return base + {{(WIDTH-12){f.i.imm_11_0[11]}}, f.i.imm_11_0};
    endfunction

    // Bytes of the access of insn at byte offset `offset` in the word: size by funct3.
    function automatic strb_t mem_mask(input [31:0] insn, input [DADDR_START-1:0] offset);
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

    // Access that the load or store in retire must make, from its insn and rs1_rdata.
    assign access_addr = mem_byte_addr(retire.insn, retire.rs1_rdata);
    assign access_mask = mem_mask(retire.insn, access_addr[DADDR_START-1:0]);

    // Bytes of data under mask are the bytes of dmem in the word at a.
    function automatic logic dmem_has(input [WIDTH-1:0] a, input strb_t mask, input [WIDTH-1:0] data);
        logic [WIDTH-1:0] ab;
        for (int b = 0; b < STRB_WIDTH; b++) begin
            ab = a + b;
            if (mask[b] && dmem_byte(ab) !== data[8*b +: 8])
                return 1'b0;
        end
        return 1'b1;
    endfunction

    // Checks of every retired instruction, values of the cycle before the rising edge;
    // register writes of the debugger.
    always @(posedge clk) begin
        if (store_check && !dmem_has(store_addr, store_mask, store_data))
            $fatal(1, "Mig1: store to %h mask %b data %h: dmem has %h", store_addr, store_mask,
                   store_data, dmem_word(store_addr));
        store_check <= 1'b0;
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
            if (retire.order !== {32'b0, retired})
                $fatal(1, "Mig1: order %0d at pc %h, expected %0d", retire.order, retire_pc, retired);
            if (retired > 0 && retire_pc !== prev_pc_wdata)
                $fatal(1, "Mig1: pc %h, the instruction before (at %h) gave next pc %h", retire_pc, prev_pc, prev_pc_wdata);
            if (retire.rs1_addr != 0 && written[retire.rs1_addr] && retire.rs1_rdata !== shadow[retire.rs1_addr])
                $fatal(1, "Mig1: pc %h read x%0d = %h, expected %h", retire_pc, retire.rs1_addr, retire.rs1_rdata, shadow[retire.rs1_addr]);
            if (retire.rs2_addr != 0 && written[retire.rs2_addr] && retire.rs2_rdata !== shadow[retire.rs2_addr])
                $fatal(1, "Mig1: pc %h read x%0d = %h, expected %h", retire_pc, retire.rs2_addr, retire.rs2_rdata, shadow[retire.rs2_addr]);
            if ((retire.rs1_addr == 0 && retire.rs1_rdata !== '0) || (retire.rs2_addr == 0 && retire.rs2_rdata !== '0))
                $fatal(1, "Mig1: pc %h read data of x0 or of an unused register is not 0", retire_pc);
            if (mem_kind(retire.insn) != 0 && !retire.trap) begin
                if (retire.mem_addr !== {access_addr[WIDTH-1:DADDR_START], {DADDR_START{1'b0}}} ||
                    (mem_kind(retire.insn) == 2'd1 ? retire.mem_rmask : retire.mem_wmask) !== access_mask ||
                    (mem_kind(retire.insn) == 2'd1 ? retire.mem_wmask : retire.mem_rmask) !== '0)
                    $fatal(1, "Mig1: pc %h accesses mem[%h] r %b w %b, expected address %h mask %b",
                           retire_pc, retire.mem_addr, retire.mem_rmask, retire.mem_wmask, access_addr, access_mask);
            end else if (retire.mem_rmask != 0 || retire.mem_wmask != 0)
                $fatal(1, "Mig1: pc %h is not a load or store (or trapped), but has a memory access", retire_pc);
            if (retire.mem_rmask != 0 && !dmem_has(retire.mem_addr, retire.mem_rmask, retire.mem_rdata))
                $fatal(1, "Mig1: load at pc %h from %h mask %b got %h, dmem has %h", retire_pc, retire.mem_addr,
                       retire.mem_rmask, retire.mem_rdata, dmem_word(retire.mem_addr));
            if (retire.trap && !expect_illegal)
                $fatal(1, "Mig1: trap at pc %h", retire_pc);
            if (trace_fd != 0) begin
                $fwrite(trace_fd, "%8d pc=%h insn=%h", cycle, retire_pc, retire.insn);
                if (retire.rd_addr != 0)
                    $fwrite(trace_fd, " x%0d <= %h", retire.rd_addr, retire.rd_wdata);
                if (retire.mem_rmask != 0)
                    $fwrite(trace_fd, " mem[%h] r %h mask %b", retire.mem_addr, retire.mem_rdata, retire.mem_rmask);
                if (retire.mem_wmask != 0)
                    $fwrite(trace_fd, " mem[%h] w %h mask %b", retire.mem_addr, retire.mem_wdata, retire.mem_wmask);
                if (retire.trap)
                    $fwrite(trace_fd, " trap");
                $fwrite(trace_fd, "\n");
            end
            if (retire.rd_addr != 0) begin
                shadow[retire.rd_addr]  <= retire.rd_wdata;
                written[retire.rd_addr] <= 1'b1;
            end
            if (retire.mem_wmask != 0) begin
                store_check <= 1'b1;
                store_addr  <= retire.mem_addr;
                store_mask  <= retire.mem_wmask;
                store_data  <= retire.mem_wdata;
            end
            prev_pc       <= retire_pc;
            prev_pc_wdata <= retire.pc_wdata;
            last_trap     <= retire.trap;
            retired       <= retired + 1;
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
        prev_pc_wdata = 0;
        last_trap     = 0;
        store_check   = 0;
        written = 0;
        dbg_req = '0;
        if (!$value$plusargs("resumes=%d", resumes)) resumes = 0;
        check_exit  = $value$plusargs("expect_exit=%d", expect_exit);
        exited      = 0;
        exit_status = 0;
        expect_sequential = $test$plusargs("expect_sequential");
        expect_regs       = $test$plusargs("expect_regs");
        expect_mem_unchanged = $test$plusargs("expect_mem_unchanged");
        riscv_test        = $test$plusargs("riscv_test");
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
            if (!illegal && semihost_call()) begin
                semihost();
                done   = exited;
                halted = exited;
            end else if (illegal || resumes == 0)
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
        @(posedge clk); #1;         // the always block has seen the last retire
        if (expect_illegal && (!last_trap || prev_pc !== halt_pc))
            $fatal(1, "Mig1: illegal=1, but the last retired instruction (at %h) is not a trap at %h",
                   prev_pc, halt_pc);
        if (illegal)
            resume_core(1'b0);     // must not restart the core, checked below
        if (check_exit && !exited)
            $fatal(1, "Mig1: no semihosting exit, halted at %h", halt_pc);
        if (exited && exit_status != (check_exit ? expect_exit : 0))
            $fatal(1, "Mig1: semihosting exit %0d, expected %0d", exit_status, check_exit ? expect_exit : 0);

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
        if (riscv_test)
            check_riscv_test();
        $display("PASS: %0d instructions retired in %0d cycles, halted at %h", retired, cycle, halt_pc);
        if (trace_file.len() != 0)
            $fclose(trace_fd);
        $finish;
    end
endmodule

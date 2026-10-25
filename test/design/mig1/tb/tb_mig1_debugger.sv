/* Debugger of Mig1 for testbenches: drives the debug port of Mig1Cpu while the core is
 * halted, and serves semihosting calls.
 *
 * The module owns dbg_req; ebreak_halt comes from TbMig1. Tasks, called by TbMig1 while
 * the core is halted:
 * - semihost_call(pc): the EBREAK at pc is a semihosting call, an EBREAK between
 *   slli x0,x0,0x1f and srai x0,x0,7 (RISC-V semihosting spec);
 * - semihost(): reads the operation (a0) and its argument (a1) through the debug port,
 *   argument blocks and strings from data memory, does the call and resumes the core,
 *   unless it is an exit. SYS_WRITEC and SYS_WRITE0 print to stdout; SYS_EXIT and
 *   SYS_EXIT_EXTENDED end the run with an exit status; other operations fail;
 * - debug_and_resume(): at a halt after EBREAK reads a0 (x10), checks it, writes
 *   a0 + 0x100 and resumes the core.
 * The trace gets a line per semihosting call and exit. Memory is read with peek() of the
 * memories of Mig1Cpu, all in mem_byte(): the one place that names them. Stops at the
 * first failure with $fatal.
 *
 * TbMig1 instantiates it.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module TbMig1Debugger import Mig1Pkg::*; (
    input  wire      clk,
    input  wire      halt,          // core halted at EBREAK
    input  wire      ebreak_halt,   // EBREAK halts the core, else it traps (from TbMig1)
    input  integer   cycle,         // cycle number of the trace (TbMig1)
    input  integer   trace_fd,      // trace file of TbMig1, 0: no trace
    input  dbg_rsp_t dbg_rsp,
    output dbg_req_t dbg_req
);
    localparam AW = MIG1_CFG.mem_addr_width;

    // Semihosting call: EBREAK between the entry and the exit no-op.
    localparam insn_t SEMIHOST_ENTRY = 32'h01f0_1013;   // slli x0, x0, 0x1f
    localparam insn_t SEMIHOST_NOP   = 32'h4070_5013;   // srai x0, x0, 7
    localparam word_t ADP_STOPPED_APPLICATION_EXIT = 32'h0002_0026;

    // Fields of dbg_req driven by the tasks.
    reg_id_t reg_id;
    logic    reg_wr;
    word_t   reg_wdata;
    logic    resume;
    word_t   halt_pc;               // byte address of the EBREAK that halted the core

    assign dbg_req = '{reg_id:      reg_id,
                       reg_wr:      reg_wr,
                       reg_wdata:   reg_wdata,
                       resume:      resume,
                       ebreak_halt: ebreak_halt};
    assign halt_pc = {dbg_rsp.halt_pc, {IADDR_START{1'b0}}};

    // The only access to the memories of Mig1Cpu: byte at address a of imem or dmem.
    // Memories wrap around: only the AW low bits of an address are used. A port of a
    // debug module (system bus access) can replace the hierarchical reference later.
    /* verilator lint_off UNUSEDSIGNAL */
    function automatic logic [7:0] mem_byte(input logic imem, input word_t a);
        return imem ? TbMig1.u_mig1_cpu.u_imem.peek(a[AW-1:0])
                    : TbMig1.u_mig1_cpu.u_dmem.peek(a[AW-1:0]);
    endfunction
    /* verilator lint_on UNUSEDSIGNAL */

    // Word at byte address a of imem or dmem, little-endian.
    function automatic word_t mem_word(input logic imem, input word_t a);
        word_t ab;
        for (int b = 0; b < 4; b++) begin
            ab = a + b;
            mem_word[8*b +: 8] = mem_byte(imem, ab);
        end
    endfunction

    // Value of register r, read through the debug port while halted.
    task automatic read_reg(input reg_id_t r, output word_t value);
        reg_id = r;
        #1;
        value = dbg_rsp.reg_rdata;
    endtask

    // resume=1 for one clock; with must_run=1 the core must run after it.
    task automatic resume_core(input logic must_run);
        resume = 1'b1;
        @(posedge clk); #1;
        resume = 1'b0;
        if (must_run && halt)
            $fatal(1, "Mig1: resume at %h, the core is still halted", halt_pc);
    endtask

    // The EBREAK at byte address pc is a semihosting call.
    function automatic logic semihost_call(input word_t pc);
        return mem_word(1'b1, pc) === INSN_EBREAK &&
               mem_word(1'b1, pc - 4) === SEMIHOST_ENTRY &&
               mem_word(1'b1, pc + 4) === SEMIHOST_NOP;
    endfunction

    // Do the semihosting call at halt_pc; resume the core unless it is an exit, which
    // ends the program with status.
    task automatic semihost(output logic exited, output integer status);
        word_t op;
        word_t arg;
        word_t a;
        word_t reason;
        exited = 1'b0;
        status = 0;
        read_reg(5'd10, op);
        read_reg(5'd11, arg);
        if (trace_fd != 0)
            $fdisplay(trace_fd, "%8d semihost op %h arg %h", cycle, op, arg);
        case (op)
            32'h03:     // SYS_WRITEC: byte at arg
                $write("%c", mem_byte(1'b0, arg));
            32'h04: begin   // SYS_WRITE0: string at arg
                a = arg;
                while (mem_byte(1'b0, a) != 0) begin
                    $write("%c", mem_byte(1'b0, a));
                    a = a + 1;
                end
            end
            32'h18: begin   // SYS_EXIT: on RV32 arg is the reason, no status
                exited = 1'b1;
                status = (arg == ADP_STOPPED_APPLICATION_EXIT) ? 0 : 1;
            end
            32'h20: begin   // SYS_EXIT_EXTENDED: block {reason, status}
                reason = mem_word(1'b0, arg);
                exited = 1'b1;
                status = (reason == ADP_STOPPED_APPLICATION_EXIT) ? mem_word(1'b0, arg + 4) : 1;
            end
            default:
                $fatal(1, "Mig1: semihosting operation %h at %h is not supported", op, halt_pc);
        endcase
        if (exited) begin
            $display("Mig1: semihosting exit %0d", status);
            if (trace_fd != 0)
                $fdisplay(trace_fd, "%8d semihost exit %0d", cycle, status);
        end else
            resume_core(1'b1);
    endtask

    // Debugger at a halt after EBREAK: read a0 (with check_a0 it must be expected_a0),
    // write a0 + 0x100, resume. One clock each for the write and the resume. Not a0 + 1:
    // that is what the EBREAK in EX computes (rs1 + imm, rs1 is read port 0 = x10), so a
    // debug write that is lost would not be noticed.
    task automatic debug_and_resume(input logic check_a0, input word_t expected_a0);
        word_t a0;
        if (mem_word(1'b1, halt_pc) !== INSN_EBREAK)
            $fatal(1, "Mig1: halted at %h, it is not EBREAK", halt_pc);
        read_reg(5'd10, a0);
        if (check_a0 && a0 !== expected_a0)
            $fatal(1, "Mig1: debug read of x10 gave %h, expected %h", a0, expected_a0);
        reg_wdata = a0 + 32'h100;
        reg_wr    = 1'b1;
        @(posedge clk); #1;
        reg_wr    = 1'b0;
        resume_core(1'b1);
    endtask

    initial begin
        reg_id    = '0;
        reg_wr    = 1'b0;
        reg_wdata = '0;
        resume    = 1'b0;
    end

endmodule

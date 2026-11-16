/* Debugger of one Mig6 PE for TbMig6: serves the semihosting calls of its core.
 *
 * EBREAK halts the core (dbg_req.ebreak_halt=1). At every halt the EBREAK must be a
 * semihosting call, an EBREAK between slli x0,x0,0x1f and srai x0,x0,7 (RISC-V semihosting
 * spec); any other halt fails the run. The operation is a0, its argument a1 (read through the
 * debug port, strings and argument blocks from the PE's memory):
 * - SYS_WRITEC, SYS_WRITE0: print to stdout, resume the core;
 * - SYS_EXIT, SYS_EXIT_EXTENDED: the program ends with a status, the core stays halted. A
 *   status other than 0 fails the run at once, whatever the other PEs do. Status 0: the
 *   hart's ID is a2 (Mig6's exit, test/design/mig6/mig6_exit.c, puts mhartid there; the
 *   debug port reads registers, not CSRs), reported to TbMig6.hart_exited(), which checks it
 *   and ends the run when every hart has exited;
 * - any other operation fails the run.
 * Memory is read with peek() of the PE's memory (TbMig6.g_pe[PE].u_pe), all in mem_byte().
 * Stops at the first failure with $fatal.
 *
 * TbMig6 instantiates one a PE.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module TbMig6Debugger import Mig6Pkg::*; #(
    parameter PE = 0                    // the PE: TbMig6.g_pe[PE]
)(
    input  wire      clk,
    input  wire      rst_n,
    input  wire      halt,              // core halted at EBREAK
    input  dbg_rsp_t dbg_rsp,
    output dbg_req_t dbg_req
);
    localparam AW = MIG6_CFG.mem_addr_width;

    // Semihosting call: EBREAK between the entry and the exit no-op.
    localparam insn_t SEMIHOST_ENTRY = 32'h01f0_1013;   // slli x0, x0, 0x1f
    localparam insn_t SEMIHOST_NOP   = 32'h4070_5013;   // srai x0, x0, 7
    localparam word_t ADP_STOPPED_APPLICATION_EXIT = 32'h0002_0026;
    // Semihosting operations (RISC-V semihosting, from the Arm semihosting spec).
    localparam word_t SYS_WRITEC        = 32'h03;
    localparam word_t SYS_WRITE0        = 32'h04;
    localparam word_t SYS_EXIT          = 32'h18;
    localparam word_t SYS_EXIT_EXTENDED = 32'h20;

    // Fields of dbg_req driven by the tasks.
    reg_id_t reg_id;
    logic    resume;
    word_t   halt_pc;                   // byte address of the EBREAK that halted the core

    assign dbg_req = '{reg_id:      reg_id,
                       reg_wr:      1'b0,
                       reg_wdata:   '0,
                       resume:      resume,
                       ebreak_halt: 1'b1};
    assign halt_pc = {dbg_rsp.halt_pc, {IADDR_START{1'b0}}};

    // The only access to the PE's memory: byte at address a (its AW low bits).
    /* verilator lint_off UNUSEDSIGNAL */
    function automatic logic [7:0] mem_byte(input word_t a);
        return TbMig6.g_pe[PE].u_pe.peek(a[AW-1:0]);
    endfunction
    /* verilator lint_on UNUSEDSIGNAL */

    // Word at byte address a, little-endian.
    function automatic word_t mem_word(input word_t a);
        for (int b = 0; b < 4; b++)
            mem_word[8*b +: 8] = mem_byte(a + word_t'(b));
    endfunction

    // Value of register r, read through the debug port while halted.
    task automatic read_reg(input reg_id_t r, output word_t value);
        reg_id = r;
        #1;
        value = dbg_rsp.reg_rdata;
    endtask

    // resume=1 for one clock; the core must run after it.
    task automatic resume_core();
        resume = 1'b1;
        @(posedge clk); #1;
        resume = 1'b0;
        if (halt)
            $fatal(1, "Mig6: PE %0d: resume at %h, the core is still halted", PE, halt_pc);
    endtask

    // The EBREAK at byte address pc is a semihosting call.
    function automatic logic semihost_call(input word_t pc);
        return mem_word(pc) === INSN_EBREAK && mem_word(pc - 4) === SEMIHOST_ENTRY &&
               mem_word(pc + 4) === SEMIHOST_NOP;
    endfunction

    // Do the semihosting call at halt_pc: print and resume, or an exit (exited = 1).
    task automatic semihost(output logic exited);
        word_t  op;
        word_t  arg;
        word_t  a;
        word_t  hart;
        integer status;
        exited = 1'b0;
        status = 0;
        read_reg(RiscvPkg::REG_A0, op);
        read_reg(RiscvPkg::REG_A1, arg);
        case (op)
            SYS_WRITEC:                 // byte at arg
                $write("%c", mem_byte(arg));
            SYS_WRITE0: begin           // string at arg
                a = arg;
                while (mem_byte(a) != 0) begin
                    $write("%c", mem_byte(a));
                    a = a + 1;
                end
            end
            SYS_EXIT: begin             // on RV32 arg is the reason, no status
                exited = 1'b1;
                status = (arg == ADP_STOPPED_APPLICATION_EXIT) ? 0 : 1;
            end
            SYS_EXIT_EXTENDED: begin    // block {reason, status}
                exited = 1'b1;
                status = (mem_word(arg) == ADP_STOPPED_APPLICATION_EXIT) ? mem_word(arg + 4) : 1;
            end
            default:
                $fatal(1, "Mig6: PE %0d: semihosting operation %h at %h is not supported", PE,
                       op, halt_pc);
        endcase
        if (!exited) begin
            resume_core();
            return;
        end
        read_reg(RiscvPkg::REG_A2, hart);
        if (status != 0)
            $fatal(1, "Mig6: PE %0d: hart %0d exited with status %0d", PE, hart, status);
        TbMig6.hart_exited(PE, hart);
    endtask

    initial begin
        logic exited;
        reg_id = '0;
        resume = 1'b0;
        exited = 1'b0;
        @(posedge rst_n);
        while (!exited) begin
            while (!halt) begin
                @(posedge clk); #1;
            end
            if (!semihost_call(halt_pc))
                $fatal(1, "Mig6: PE %0d halted at %h, not at a semihosting call", PE, halt_pc);
            semihost(exited);
        end
    end

endmodule

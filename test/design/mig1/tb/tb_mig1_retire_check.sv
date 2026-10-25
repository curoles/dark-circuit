/* Retire checks of Mig1: every retired instruction against the program, the memories and a
 * shadow copy of the registers; the retire lines of the trace.
 *
 * retire is the RVFI trace of the core (see Mig1Pkg). Checks of every retired instruction:
 * - retire.insn is the imem word at pc_rdata: fetch gets the right instruction,
 * - the first retired pc is the reset address, order counts 0, 1, 2, ...,
 * - pc_rdata is pc_wdata of the previous retired instruction (control flow),
 * - rs1_rdata, rs2_rdata are the shadow registers (registers read), 0 for x0,
 * - load or store: mem_addr and the mask are the access of the instruction:
 *   address rs1_rdata + imm, size by funct3 (computed here from insn),
 * - load: bytes of mem_rdata under mem_rmask are the bytes of dmem,
 * - store: when it retires, dmem has the bytes of mem_wdata under mem_wmask (the store
 *   wrote one cycle before, in EX; a younger store writes at the end of the retire cycle),
 * - traps only with allow_trap,
 * - nothing retires while halted,
 * - no X or Z in retire (Icarus only, Verilator is 2-state),
 * - with +expect_sequential: every pc is the previous pc + 4 (straight-line code).
 * Register writes of retire (rd_addr, rd_wdata) and of the debugger (dbg_req while halt)
 * are kept in a shadow copy of the registers. The trace gets a line per retired
 * instruction, debugger register write and resume. Memory is read with peek() of the
 * memories of Mig1Cpu, all in mem_byte(): the one place that names them. Stops at the
 * first failure with $fatal.
 *
 * TbMig1 instantiates it; it reads its ports, TbMig1 reads its outputs.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module TbMig1RetireCheck import Mig1Pkg::*, RiscvPkg::*; (
    input  wire         clk,
    input  wire         rst_n,              // synchronous reset, active low
    input  wire         halt,               // core halted: the debugger may write registers
    input  wire         halted,             // TbMig1 handles a halt: nothing may retire
    input  wire         allow_trap,         // a retired trap is no failure
    // All fields but bubble are used (bubbles: TbMig1BubbleCheck).
    /* verilator lint_off UNUSEDSIGNAL */
    input  retire_t     retire,
    /* verilator lint_on UNUSEDSIGNAL */
    // Only reg_id, reg_wr, reg_wdata and resume are used: writes of the debugger.
    /* verilator lint_off UNUSEDSIGNAL */
    input  dbg_req_t    dbg_req,
    /* verilator lint_on UNUSEDSIGNAL */
    input  integer      cycle,              // cycle number of the trace (TbMig1)
    input  integer      trace_fd,           // trace file of TbMig1, 0: no trace
    output integer      retired,            // instructions retired so far
    output integer      traps,              // retired instructions that trapped
    output logic        ebreak_trapped,     // an EBREAK has trapped
    output word_t       shadow [32],        // registers written by retire and the debugger
    output logic [31:0] written             // bit r: shadow[r] was written
);
    import RiscvInstrPkg::*;

    localparam AW = MIG1_CFG.mem_addr_width;

    logic  expect_sequential;               // +expect_sequential
    word_t retire_pc;                       // byte address
    word_t prev_pc;
    word_t prev_pc_wdata;                   // next pc told by the previous retired instruction
    word_t access_addr;                     // load or store in retire: byte address
    strb_t access_mask;                     // its bytes

    assign retire_pc = retire.pc_rdata;

    // The only access to the memories of Mig1Cpu: byte at address a of imem or dmem.
    // Memories wrap around: only the AW low bits of an address are used.
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
            if (mask[b] && mem_byte(1'b0, ab) !== data[8*b +: 8])
                return 1'b0;
        end
        return 1'b1;
    endfunction

    // Checks of every retired instruction

    // Register r read by the instruction in retire gave data: the shadow value, 0 for x0
    // and for an unused register (r = 0).
    task automatic check_read(input reg_id_t r, input word_t data);
        if (r == 0 && data !== '0)
            $fatal(1, "Mig1: pc %h read data of x0 or of an unused register is not 0", retire_pc);
        if (r != 0 && written[r] && data !== shadow[r])
            $fatal(1, "Mig1: pc %h read x%0d = %h, expected %h", retire_pc, r, data, shadow[r]);
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
            $fatal(1, "Mig1: pc %h accesses mem[%h] r %b w %b, expected address %h mask %b",
                   retire_pc, retire.mem_addr, retire.mem_rmask, retire.mem_wmask,
                   access_addr, access_mask);
    endtask

    // Values of the cycle before the rising edge; also the register writes of the debugger.
    always @(posedge clk) begin
        if (rst_n && retire.valid) begin
`ifndef VERILATOR
            if ($isunknown(retire))
                $fatal(1, "Mig1: X or Z in retire: %h", retire);
`endif
            if (halted)
                $fatal(1, "Mig1: instruction at %h retired after halt", retire_pc);
            if (retired == 0 && retire_pc !== MIG1_CFG.rst_addr)
                $fatal(1, "Mig1: first instruction at %h, expected reset address %h",
                       retire_pc, MIG1_CFG.rst_addr);
            if (expect_sequential && retired > 0 && retire_pc !== prev_pc + 4)
                $fatal(1, "Mig1: pc %h after %h, expected %h", retire_pc, prev_pc, prev_pc + 4);
            if (retire.insn !== mem_word(1'b1, retire_pc))
                $fatal(1, "Mig1: insn %h at pc %h, imem has %h",
                       retire.insn, retire_pc, mem_word(1'b1, retire_pc));
            if (retire.order !== {32'b0, retired})
                $fatal(1, "Mig1: order %0d at pc %h, expected %0d",
                       retire.order, retire_pc, retired);
            if (retired > 0 && retire_pc !== prev_pc_wdata)
                $fatal(1, "Mig1: pc %h, the instruction before (at %h) gave next pc %h",
                       retire_pc, prev_pc, prev_pc_wdata);
            check_read(retire.rs1_addr, retire.rs1_rdata);
            check_read(retire.rs2_addr, retire.rs2_rdata);
            if (mem_kind(retire.insn) != MEM_NONE && !retire.trap)
                check_access();
            else if (retire.mem_rmask != 0 || retire.mem_wmask != 0)
                $fatal(1, "Mig1: pc %h is not a load or store (or trapped), but has a memory access",
                       retire_pc);
            if (retire.mem_rmask != 0 &&
                !dmem_has(retire.mem_addr, retire.mem_rmask, retire.mem_rdata))
                $fatal(1, "Mig1: load at pc %h from %h mask %b got %h, dmem has %h",
                       retire_pc, retire.mem_addr, retire.mem_rmask, retire.mem_rdata,
                       mem_word(1'b0, retire.mem_addr));
            if (retire.mem_wmask != 0 &&
                !dmem_has(retire.mem_addr, retire.mem_wmask, retire.mem_wdata))
                $fatal(1, "Mig1: store at %h to %h mask %b data %h: dmem has %h",
                       retire_pc, retire.mem_addr, retire.mem_wmask, retire.mem_wdata,
                       mem_word(1'b0, retire.mem_addr));
            if (retire.trap && !allow_trap)
                $fatal(1, "Mig1: trap at pc %h", retire_pc);
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

    initial begin
        expect_sequential = $test$plusargs("expect_sequential");
        retired           = 0;
        traps             = 0;
        ebreak_trapped    = 1'b0;
        written           = '0;
        prev_pc           = '0;
        prev_pc_wdata     = '0;
    end

endmodule

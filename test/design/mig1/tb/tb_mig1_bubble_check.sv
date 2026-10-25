/* Bubble checks of Mig1: every cycle that retires no instruction retires a bubble with a
 * reason that fits the instructions around it; counts per reason.
 *
 * A cycle out of reset and not halted retires an instruction or a bubble: retire.bubble
 * tells why (bubble_e, Mig1Pkg). Checks: an instruction has no bubble reason, a bubble has
 * one; a redirect bubble (branch, jump, return, trap, MRET) follows the instruction of that
 * class that retired right before it, at most 2; a load-use bubble follows a load, and the
 * next instruction reads its rd; division bubbles come right before a division; fill
 * bubbles only before the first instruction after reset or resume. The trace gets a line
 * per bubble; report() at the end of the run prints the count per reason and checks that
 * every counted cycle retired an instruction or a bubble. Stops at the first failure with
 * $fatal.
 *
 * TbMig1 instantiates it; it reads its ports, and TbMig1 calls report().
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module TbMig1BubbleCheck import Mig1Pkg::*, RiscvPkg::*, TbMig1Pkg::*; (
    input  wire     clk,
    input  wire     rst_n,          // synchronous reset, active low
    input  wire     halt,           // core halted: no cycle to count
    input  wire     resume,         // debugger resumes the core: the pipeline fills again
    // Only valid, bubble, trap, insn, pc_rdata, rs1_addr, rs2_addr, rd_addr and mem_rmask
    // are used.
    /* verilator lint_off UNUSEDSIGNAL */
    input  retire_t retire,
    /* verilator lint_on UNUSEDSIGNAL */
    input  integer  cycle,          // cycle number of the trace (TbMig1)
    input  integer  trace_fd        // trace file of TbMig1, 0: no trace
);
    import RiscvInstrPkg::*;

    integer  core_cycles;           // cycles out of reset and not halted
    integer  retired;
    integer  bubbles [1 << $bits(bubble_e)];    // bubbles[b]: bubbles of reason b
    word_t   prev_pc;               // pc of the last retired instruction
    bubble_e redirect_class;        // reason of the bubbles the last retired insn makes
    integer  redirect_bubbles;      // bubbles since the last retired instruction
    logic    filling;               // nothing retired since reset or resume
    reg_id_t load_rd;               // the last retired instruction loads rd, 0: none
    reg_id_t use_rd;                // after a load-use bubble: the next one reads it
    logic    div_pending;           // after a division bubble: the next one divides

    // JALR is a return (pops the return-address stack, RISC-V hints) when rs1 is x1 or
    // x5, unless rd = rs1.
    function automatic logic is_return(input insn_t insn);
        insn_fmt_t f;
        logic      rd_link;
        logic      rs1_link;
        f.word   = insn;
        rd_link  = f.i.rd == 5'd1 || f.i.rd == 5'd5;
        rs1_link = f.i.rs1 == 5'd1 || f.i.rs1 == 5'd5;
        return rs1_link && (!rd_link || f.i.rd != f.i.rs1);
    endfunction

    // Reason of the bubbles that a retired instruction (trap: it trapped) makes when it
    // redirects fetch; BUBBLE_NONE when it can not redirect.
    function automatic bubble_e redirect_class_of(input logic trap, input insn_t insn);
        if (trap)
            return BUBBLE_TRAP;
        casez (insn)
            MRET:    return BUBBLE_XRET;
            JAL:     return BUBBLE_DIR_JUMP;
            JALR:    return is_return(insn) ? BUBBLE_RET : BUBBLE_INDIR_JUMP;
            BEQ, BNE, BLT, BGE, BLTU, BGEU:
                     return BUBBLE_COND_BRANCH;
            default: return BUBBLE_NONE;
        endcase
    endfunction

    function automatic logic is_div(input insn_t insn);
        casez (insn)
            DIV, DIVU, REM, REMU: return 1'b1;
            default:              return 1'b0;
        endcase
    endfunction

    // A bubble retires in this cycle: its reason must fit the instructions around it.
    task automatic check_bubble(input bubble_e b);
        case (b)
            BUBBLE_NONE:
                $fatal(1, "Mig1: cycle %0d: nothing retires and no bubble reason", cycle);
            BUBBLE_FILL:
                if (!filling)
                    $fatal(1, "Mig1: cycle %0d: fill bubble after an instruction retired", cycle);
            BUBBLE_LOAD_USE:
                if (load_rd == 0)
                    $fatal(1, "Mig1: cycle %0d: load-use bubble, no load retired before it", cycle);
            BUBBLE_DIV: ;   // the next retired instruction must be a division
            default:        // redirect classes
                if (b != redirect_class || redirect_bubbles >= 2)
                    $fatal(1, "Mig1: cycle %0d: %s bubble after pc %h (%s, %0d bubbles before)",
                           cycle, bubble_name(b), prev_pc, bubble_name(redirect_class),
                           redirect_bubbles);
        endcase
        if (div_pending && b != BUBBLE_DIV)
            $fatal(1, "Mig1: cycle %0d: %s bubble between division bubbles and the division",
                   cycle, bubble_name(b));
    endtask

    // End of the run (TbMig1 calls it): bubbles per reason; every counted cycle retired an
    // instruction or a bubble.
    task automatic report;
        string  s;
        integer total;
        total = 0;
        s     = "";
        for (int k = 0; k < (1 << $bits(bubble_e)); k++)
            if (bubbles[k] != 0) begin
                total = total + bubbles[k];
                s     = {s, $sformatf(" %s %0d", bubble_name(bubble_e'(k)), bubbles[k])};
            end
        if (core_cycles != retired + total)
            $fatal(1, "Mig1: %0d cycles, but %0d retired + %0d bubbles",
                   core_cycles, retired, total);
        $display("Mig1: %0d cycles = %0d retired + %0d bubbles:%s", core_cycles, retired, total, s);
        if (trace_fd != 0)
            $fdisplay(trace_fd, "%0d cycles = %0d retired + %0d bubbles:%s",
                      core_cycles, retired, total, s);
    endtask

    // Values of the cycle before the rising edge.
    always @(posedge clk) begin
        if (rst_n && !halt) begin
            core_cycles <= core_cycles + 1;
            if (!retire.valid) begin
                check_bubble(retire.bubble);
                if (trace_fd != 0)
                    $fdisplay(trace_fd, "%8d bubble %s", cycle, bubble_name(retire.bubble));
                bubbles[retire.bubble] <= bubbles[retire.bubble] + 1;
                redirect_bubbles       <= redirect_bubbles + 1;
                if (retire.bubble == BUBBLE_LOAD_USE)
                    use_rd <= load_rd;
                if (retire.bubble == BUBBLE_DIV)
                    div_pending <= 1'b1;
            end
        end
        if (halt && resume)
            filling <= 1'b1;
        if (rst_n && retire.valid) begin
            if (retire.bubble != BUBBLE_NONE)
                $fatal(1, "Mig1: pc %h retires with bubble reason %s",
                       retire.pc_rdata, bubble_name(retire.bubble));
            if (use_rd != 0 && retire.rs1_addr != use_rd && retire.rs2_addr != use_rd)
                $fatal(1, "Mig1: pc %h after a load-use bubble does not read x%0d",
                       retire.pc_rdata, use_rd);
            if (div_pending && !is_div(retire.insn))
                $fatal(1, "Mig1: pc %h after division bubbles is not a division", retire.pc_rdata);
            prev_pc          <= retire.pc_rdata;
            retired          <= retired + 1;
            redirect_class   <= redirect_class_of(retire.trap, retire.insn);
            redirect_bubbles <= 0;
            load_rd          <= retire.mem_rmask != 0 ? retire.rd_addr : '0;
            use_rd           <= '0;
            div_pending      <= 1'b0;
            filling          <= 1'b0;
        end
    end

    initial begin
        core_cycles      = 0;
        retired          = 0;
        foreach (bubbles[k])
            bubbles[k] = 0;
        prev_pc          = '0;
        redirect_class   = BUBBLE_NONE;
        redirect_bubbles = 0;
        filling          = 1'b1;
        load_rd          = '0;
        use_rd           = '0;
        div_pending      = 1'b0;
    end

endmodule

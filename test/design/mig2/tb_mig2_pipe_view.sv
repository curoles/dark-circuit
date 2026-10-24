/* Pipeline view of Mig2: follows every instruction through the stages, checks the view
 * against pipe_trace and writes it as a Konata log.
 *
 * pipe_trace (Mig2Pkg) has the slot of every stage and how the slots move at the rising
 * edge. The module keeps the instruction of every stage, moves it as pipe_trace tells,
 * and checks in every cycle out of reset that its stages and the reported slots agree
 * (valid and pc). +kanata=<file> writes the view as a Konata log (Kanata format 0004, tab
 * separated): a row per instruction, stages IF ID EX MEM, the instructions of the wrong
 * path flushed; label: pc and instruction word, tooltip: the bubbles before it. Cycles in
 * messages count from reset, like the log. Stops at the first mismatch with $fatal.
 *
 * TbMig2 instantiates it; it only reads its ports.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
module TbMig2PipeView import Mig2Pkg::*, TbMig2Pkg::*; (
    input  wire         clk,
    input  wire         rst_n,          // synchronous reset, active low
    input  wire         halt,           // core halted: an empty slot is no bubble
    // Only insn, trap and order are used: label and end of a retired instruction.
    /* verilator lint_off UNUSEDSIGNAL */
    input  retire_t     retire,
    /* verilator lint_on UNUSEDSIGNAL */
    input  pipe_trace_t pipe_trace      // slots and moves, from Mig2Core
);
    localparam S_IF = 0, S_ID = 1, S_EX = 2, S_MEM = 3;

    string  kanata_file;
    integer kanata_fd;                  // 0: no Konata log
    integer cycle;                      // cycles out of reset, as in the log
    integer stage_id [4];               // instruction in IF, ID, EX, MEM/WB; -1: none
    iaddr_t stage_pc [4];
    integer next_id;                    // id of the next instruction IF requests
    integer bubbles [1 << $bits(bubble_e)];     // bubbles since the last retire

    function automatic string stage_name(input integer s);
        case (s)
            S_IF:    return "IF";
            S_ID:    return "ID";
            S_EX:    return "EX";
            default: return "MEM";
        endcase
    endfunction

    // The tracked instruction of stage s against the slot pipe_trace reports for it (an
    // instruction at pc, or a bubble).
    task automatic check_slot(input integer s, input logic valid, input iaddr_t pc);
        if ((stage_id[s] >= 0) !== valid || (valid && stage_pc[s] !== pc))
            $fatal(1, "Mig2: cycle %0d: %s has %s, pipe_trace reports %s", cycle,
                   stage_name(s),
                   stage_id[s] >= 0 ? $sformatf("pc %h", {stage_pc[s], 2'b00}) : "none",
                   valid ? $sformatf("pc %h", {pc, 2'b00}) : "a bubble");
    endtask

    // Konata log (Kanata format 0004, tab separated): stage s starts for instruction id;
    // instruction id ends, retired or flushed. Nothing without +kanata.
    task automatic kanata_stage(input integer id, input integer s);
        if (kanata_fd != 0)
            $fdisplay(kanata_fd, "S\t%0d\t0\t%s", id, stage_name(s));
    endtask

    task automatic kanata_flush(input integer id);
        if (kanata_fd != 0)
            $fdisplay(kanata_fd, "R\t%0d\t0\t1", id);
    endtask

    // The instruction in MEM/WB retires: its word into the label, the bubbles before it
    // into the tooltip.
    task automatic kanata_retire(input integer id);
        string s;
        if (kanata_fd != 0) begin
            s = "";
            for (int k = 0; k < (1 << $bits(bubble_e)); k++)
                if (bubbles[k] != 0)
                    s = {s, $sformatf(" %s %0d", bubble_name(bubble_e'(k)), bubbles[k])};
            $fdisplay(kanata_fd, "L\t%0d\t0\t: %h", id, retire.insn);
            if (retire.trap)
                $fdisplay(kanata_fd, "L\t%0d\t0\t trap", id);
            if (s.len() != 0)
                $fdisplay(kanata_fd, "L\t%0d\t1\tbubbles before:%s", id, s);
            $fdisplay(kanata_fd, "R\t%0d\t%0d\t0", id, retire.order[31:0]);
        end
        foreach (bubbles[k])
            bubbles[k] = 0;
    endtask

    // One cycle, at its rising edge: check the tracked stages against the slots, log a
    // request of this cycle, then move the instructions as pipe_trace tells.
    task automatic step;
        integer old_if;
        integer old_id;
        integer old_ex;
        iaddr_t old_if_pc;
        iaddr_t old_id_pc;
        iaddr_t old_ex_pc;
        logic   id_to_ex;   // the instruction in ID goes to EX
        check_slot(S_ID, pipe_trace.id.valid, pipe_trace.id.pc);
        check_slot(S_EX, pipe_trace.ex.valid, pipe_trace.ex.pc);
        check_slot(S_MEM, pipe_trace.mem.valid, pipe_trace.mem.pc);
        if (!pipe_trace.mem.valid && !halt)
            bubbles[pipe_trace.mem.bubble] = bubbles[pipe_trace.mem.bubble] + 1;
        stage_id[S_IF] = -1;
        if (pipe_trace.if_req) begin
            stage_id[S_IF] = next_id;
            stage_pc[S_IF] = pipe_trace.if_pc;
            next_id        = next_id + 1;
            if (kanata_fd != 0) begin
                $fdisplay(kanata_fd, "I\t%0d\t%0d\t0", stage_id[S_IF], stage_id[S_IF]);
                $fdisplay(kanata_fd, "L\t%0d\t0\t%h", stage_id[S_IF], {pipe_trace.if_pc, 2'b00});
            end
            kanata_stage(stage_id[S_IF], S_IF);
        end
        if (kanata_fd != 0)
            $fdisplay(kanata_fd, "C\t1");

        // Moves at the rising edge, MEM/WB first.
        old_if    = stage_id[S_IF];
        old_id    = stage_id[S_ID];
        old_ex    = stage_id[S_EX];
        old_if_pc = stage_pc[S_IF];
        old_id_pc = stage_pc[S_ID];
        old_ex_pc = stage_pc[S_EX];
        id_to_ex  = !pipe_trace.ex_stall && !pipe_trace.ex_flush;
        if (id_to_ex && pipe_trace.id_stall)
            $fatal(1, "Mig2: cycle %0d: pipe_trace: ID both goes to EX and stalls", cycle);
        if (old_if >= 0 && pipe_trace.id_stall)
            $fatal(1, "Mig2: cycle %0d: pipe_trace: IF requests while ID stalls", cycle);
        // MEM/WB retires; EX goes to MEM/WB unless it stalls.
        if (stage_id[S_MEM] >= 0)
            kanata_retire(stage_id[S_MEM]);
        stage_id[S_MEM] = pipe_trace.ex_stall ? -1 : old_ex;
        stage_pc[S_MEM] = old_ex_pc;
        if (stage_id[S_MEM] >= 0)
            kanata_stage(old_ex, S_MEM);
        // EX keeps its instruction (stall), takes ID's, or gets a bubble (flush).
        if (!pipe_trace.ex_stall) begin
            stage_id[S_EX] = id_to_ex ? old_id : -1;
            stage_pc[S_EX] = old_id_pc;
            if (stage_id[S_EX] >= 0)
                kanata_stage(old_id, S_EX);
        end
        // ID keeps its instruction (stall), takes the request of IF, or gets a bubble; an
        // instruction of ID that neither stays nor goes to EX is flushed (wrong path), so
        // is a request that a redirect drops.
        if (old_id >= 0 && !id_to_ex && !pipe_trace.id_stall)
            kanata_flush(old_id);
        if (!pipe_trace.id_stall) begin
            stage_id[S_ID] = pipe_trace.redirect ? -1 : old_if;
            stage_pc[S_ID] = old_if_pc;
            if (stage_id[S_ID] >= 0)
                kanata_stage(old_if, S_ID);
        end
        if (old_if >= 0 && pipe_trace.redirect)
            kanata_flush(old_if);
        cycle = cycle + 1;
    endtask

    always @(posedge clk)
        if (rst_n)
            step();

    initial begin
        cycle   = 0;
        next_id = 0;
        foreach (stage_id[s])
            stage_id[s] = -1;
        foreach (bubbles[k])
            bubbles[k] = 0;

        // +kanata=<file> writes the view as a Konata log.
        if ($value$plusargs("kanata=%s", kanata_file)) begin
            kanata_fd = $fopen(kanata_file, "w");
            if (kanata_fd == 0)
                $fatal(1, "Mig2: can not open Konata log %s", kanata_file);
            $fdisplay(kanata_fd, "Kanata\t0004");
            $fdisplay(kanata_fd, "C=\t0");
            $display("Mig2: Konata log in %s", kanata_file);
        end else
            kanata_fd = 0;
    end

    // End of the simulation: instructions still in ID, EX or MEM/WB end as flushed (Konata
    // needs an end for every instruction; the request in IF has moved on already).
    final
        if (kanata_fd != 0) begin
            for (int s = S_ID; s <= S_MEM; s++)
                if (stage_id[s] >= 0)
                    kanata_flush(stage_id[s]);
            $fclose(kanata_fd);
        end

endmodule

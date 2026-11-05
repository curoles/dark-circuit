/* Mig3 fetch: program counter, branch target buffer, instruction memory requests, the kept
 * line, and the fetch stages IF and IF2 before ID.
 *
 * IF asks imem for the instruction at pc (a request on the imem channel) and keeps one
 * request in flight: it asks when none is pending or its answer comes in this cycle, and only
 * while the instruction can go into IF2 at once (ID does not stall). The request imem takes
 * goes into IF2 at that edge; its line comes 1 or more clocks later, and the slot waits in
 * IF2 until it is here (if2_wait; the line is kept while ID stalls). From IF2 the instruction
 * and its word go into ID at the next edge through a register, so ID decodes a word from a
 * flop, never imem's answer of the same clock (kb rtl/design/mig3/fetch_stage); IF2 sends ID
 * a bubble of reason imem while its slot waits. A request imem does not take is not kept:
 * fetch asks again in the next cycle, for what is right then; imem acts only on a request it
 * takes (an exception to the valid/ready rule 2 of AGENTS.md, see kb
 * rtl/design/mig2/fetch_waits).
 * The kept line: fetch keeps the line of every answer it uses (line_q). When the next
 * instruction is in it, it goes into IF2 with its word at once, without a request to imem
 * (kb rtl/design/mig3/fetch_line): in straight code the second word of a line, and right
 * after a miss the second word of the line arriving (asked of imem in that refill clock, the
 * cache would replay it at the place the refill writes). While a line arrives only that line
 * counts, since line_q takes it at that edge. Not when uncached: then every instruction is a
 * request, with the memory's own timing. A redirect keeps the line (its words are right).
 * Reset loads CFG.rst_addr (reset is a jump), then pc advances with every instruction that
 * enters IF2. ctrl.redirect=1 loads ctrl.target (taken branch or jump) and drops the
 * instruction of this cycle, the one in IF2 and the one that would enter ID (bubbles of
 * reason ctrl.why): the answer of a dropped request is thrown away when it comes. ctrl.run=0
 * (reset, halt) stops fetch and drops the instructions that would enter IF2 and ID: they get
 * fill bubbles. ctrl.stall=1 keeps pc, IF2 and ID, so the instruction in ID stays for another
 * cycle.
 * The BTB (BranchTargetBuffer) looks up pc in the same cycle: a hit predicted taken loads
 * its target instead of pc + 1 when the instruction enters IF2, without a bubble; a redirect
 * wins over it. What the BTB said goes with the instruction to ID (btb_pred), and so does the
 * address fetch went to after it (id_next_pc: pc when the instruction leaves IF2, pc + 1 or
 * the BTB's target); Mig3Control checks the prediction in ID with them, updates the BTB from
 * EX (btb_update) and clears a wrong entry from ID (btb_inval). The BTB sees the low
 * btb_index_width + btb_tag_width bits of the word address (Mig3ConfigPkg).
 *
 *   pc --> in the kept line? --yes-------------------+
 *     |                                              v
 *     +--> no: imem request (IF, BTB) --> IF2 slot (waits for its line) --> word --> register
 *                                         line: answer now, or kept (line_q)          --> ID
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "dark_circuit_assert.svh"

module Mig3Fetch import Mig3Pkg::*; #(
    parameter mig3_cfg_t CFG = MIG3_CFG   // configuration, see Mig3ConfigPkg
)(
    input  wire         clk,
    input  wire         rst_n,            // synchronous reset, active low
    input  wire         uncached,         // every instruction is a request (the caches' mode)
    input  fetch_ctrl_t ctrl,             // run, stall, redirect and target, from Mig3Control
    // Only the low bits of the pcs are used: those the BTB sees.
    /* verilator lint_off UNUSEDSIGNAL */
    input  btb_update_t btb_update,       // a branch or JAL completed in EX: the BTB learns it
    input  btb_inval_t  btb_inval,        // the BTB sent fetch where the insn in ID does not go
    /* verilator lint_on UNUSEDSIGNAL */
    output imem_req_t   imem_req,         // request to imem: valid and word address
    input  imem_rsp_t   imem_rsp,         // imem takes it (ready), the answer (valid, line)
    output fetch_t      fetch,            // the instruction in ID (a bubble while none)
    output insn_t       insn,             // its word
    output btb_pred_t   btb_pred,         // what the BTB said for the instruction in ID
    output iaddr_t      id_next_pc,       // the address fetch went to after it
    output wire         if_taken,         // an instruction enters IF2 at this edge
    output fetch_t      if2,              // the slot of IF2: valid also while it waits
    output wire         if2_wait,         // the slot in IF2 waits for its line from imem
    output wire         if2_keep          // IF2 keeps its slot at the rising edge
);
    localparam iaddr_t RST_PC       = CFG.rst_addr[WIDTH-1:IADDR_START];   // word address
    localparam         BTB_PC_WIDTH = CFG.btb_index_width + CFG.btb_tag_width; // pc bits it sees

    logic      rst;         // reset active
    iaddr_t    pc;          // address of the instruction fetch wants in this cycle
    logic      want;        // fetch wants it now: it can go into IF2 at once
    logic      line_hit;    // it is in the kept line (or in the line arriving now)
    logic      mem_taken;   // imem takes the request of this cycle
    logic      line_taken;  // the instruction enters IF2 from the kept line
    logic      taken;       // the instruction enters IF2 at this edge: one of the two
    logic      pending;     // a request imem took is not answered yet
    logic      drop;        // its answer is thrown away: its slot was dropped
    logic      answer;      // the answer of the pending request comes in this cycle
    logic      got;         // the line of the slot in IF2 is kept (came earlier, or line_q)
    logic      have_word;   // the word of the slot is here: kept, or the answer of now
    line_t     line_q;      // the kept line
    laddr_t    line_addr_q; // its line address
    logic      line_valid;  // line_q holds a line
    line_t     if2_line;    // the line of the slot in IF2: the answer of now, or kept
    insn_t     if2_insn;    // the word of the slot in IF2, when it is here
    fetch_t    slot;        // IF2: the instruction there
    btb_pred_t slot_btb;    // what the BTB said for it
    fetch_t    to_id;       // what goes into ID at the edge: the slot with its word, or a bubble
    logic      predict;     // the BTB sends fetch to its target
    logic      jump;        // load jump_pc: reset, redirect or prediction
    iaddr_t    jump_pc;     // address of the jump
    btb_pred_t btb_d;       // what the BTB says for the instruction of this cycle
    iaddr_t    btb_target;  // target of the entry of pc; means something only on a hit

    assign rst    = !rst_n;
    assign answer = imem_rsp.valid;

    // @kb: rtl/design/mig2/fetch_waits
    // @kb: rtl/design/mig3/fetch_line
    assign want       = ctrl.run && !ctrl.stall && (!pending || answer);
    assign line_hit   = !uncached &&
                        (answer && !drop ? pc[WIDTH-1:LINE_START] == slot.pc[WIDTH-1:LINE_START]
                                         : line_valid && pc[WIDTH-1:LINE_START] == line_addr_q);
    assign imem_req.valid = want && !line_hit;
    assign imem_req.addr  = pc;
    assign mem_taken  = imem_req.valid && imem_rsp.ready;
    assign line_taken = want && line_hit;
    assign taken      = mem_taken || line_taken;
    assign if_taken   = taken;

    // pc moves on when the instruction enters IF2; a redirect drops the instruction of this
    // cycle, and with it what the BTB said about it: jump_pc takes ctrl.target first.
    assign predict = taken && btb_d.taken;
    assign jump    = rst || ctrl.redirect || predict;
    assign jump_pc = rst ? RST_PC : ctrl.redirect ? ctrl.target : btb_target;

    // @kb: rtl/design/mig2/dropped_next_pc_without_prg_counter
    PrgCounter #(.ADDR_WIDTH(WIDTH), .INSN_SIZE($bits(insn_t) / 8)) u_prg_counter(
        .clk, .en(taken), .jump, .jump_addr(jump_pc), .pc);

    // @kb: rtl/design/mig2/btb_in_if
    // @kb: rtl/design/mig2/dropped_registered_btb_update
    BranchTargetBuffer #(.INDEX_WIDTH(CFG.btb_index_width), .TAG_WIDTH(CFG.btb_tag_width),
                         .TARGET_WIDTH($bits(iaddr_t))) u_branch_target_buffer(
        .clk, .rst_n,
        .lookup_pc(pc[IADDR_START +: BTB_PC_WIDTH]), .lookup_hit(btb_d.hit),
        .lookup_taken(btb_d.taken), .lookup_target(btb_target),
        .lookup_counter(btb_d.counter),
        .update_en(btb_update.en), .update_pc(btb_update.pc[IADDR_START +: BTB_PC_WIDTH]),
        .update_hit(btb_update.hit), .update_counter(btb_update.counter),
        .update_taken(btb_update.taken), .update_target(btb_update.target),
        .inval_en(btb_inval.en), .inval_pc(btb_inval.pc[IADDR_START +: BTB_PC_WIDTH]));

    // IF2 keeps its slot while ID stalls, or while the slot waits for its line, unless a
    // redirect or a halt drops it; else it takes the instruction that enters now, or a bubble.
    assign have_word = got || (answer && !drop);
    assign if2_wait  = slot.valid && !have_word;
    assign if2_keep  = ctrl.stall || (if2_wait && ctrl.run && !ctrl.redirect);

    fetch_t slot_d;
    assign slot_d = '{valid:  taken && !ctrl.redirect,
                      bubble: ctrl.redirect ? ctrl.why : !ctrl.run ? BUBBLE_FILL :
                              taken ? BUBBLE_NONE : BUBBLE_IMEM,
                      pc:     pc};

    Mig3PipeReg #(.T(fetch_t)) u_mig3_pipe_reg_if_if2(
        .clk, .rst_n, .stall(if2_keep), .flush(1'b0), .why(BUBBLE_NONE), .d(slot_d),
        .q(slot));

    // What the BTB said for the slot: the same moves as the slot; no reset, it means nothing
    // while the slot is a bubble.
    always_ff @(posedge clk)
        if (!if2_keep)
            slot_btb <= btb_d;

    // The request in flight and its answer: thrown away when it was taken in a redirect
    // cycle, or when IF2 drops its slot while it is pending. A slot from the kept line has
    // its line at once.
    always_ff @(posedge clk)
        if (!rst_n) begin
            pending <= 1'b0;
            drop    <= 1'b0;
            got     <= 1'b0;
        end else begin
            pending <= mem_taken || (pending && !answer);
            drop    <= mem_taken ? ctrl.redirect : pending && !answer && (drop || !if2_keep);
            got     <= if2_keep ? have_word : line_taken && !ctrl.redirect;
        end

    // The kept line: the line of every answer used (a dropped answer's slot is gone, its
    // address with it). No reset of the line, it means nothing while line_valid is 0.
    always_ff @(posedge clk)
        if (!rst_n)
            line_valid <= 1'b0;
        else if (answer && !drop)
            line_valid <= 1'b1;

    always_ff @(posedge clk)
        if (answer && !drop) begin
            line_q      <= imem_rsp.data;
            line_addr_q <= slot.pc[WIDTH-1:LINE_START];
        end

    // The word of the slot in IF2, from its line (the answer of this cycle, or kept): the
    // word index is the slot's pc, a flop; the late answer goes only into ID's register.
    assign if2_line = answer ? imem_rsp.data : line_q;
    if (LINE_START == IADDR_START) begin: g_one_word
        assign if2_insn = insn_t'(if2_line);
    end else begin: g_words
        word_t [LINE_WORDS-1:0] words;      // the line as words
        assign words    = if2_line;
        assign if2_insn = insn_t'(words[slot.pc[LINE_START-1:IADDR_START]]);
    end

    assign if2   = slot;
    assign to_id = '{valid:  slot.valid && have_word,
                     bubble: if2_wait ? BUBBLE_IMEM : slot.bubble,
                     pc:     slot.pc};

    // IF2 -> ID: the instruction with its word, or a bubble; kept while ID stalls, a bubble
    // of reason ctrl.why on a redirect, a fill bubble while fetch stops (reset, halt: like
    // IF2, ID takes nothing then). The word, what the BTB said and the address fetch went to
    // after the instruction (pc now: it moved on when the instruction entered IF2, and holds
    // until the next one does) move with it; no reset, they mean nothing while ID holds a
    // bubble.
    // @kb: rtl/design/mig3/fetch_stage
    Mig3PipeReg #(.T(fetch_t)) u_mig3_pipe_reg_if2_id(
        .clk, .rst_n, .stall(ctrl.stall), .flush(ctrl.redirect || !ctrl.run),
        .why(ctrl.redirect ? ctrl.why : BUBBLE_FILL), .d(to_id), .q(fetch));

    always_ff @(posedge clk)
        if (!ctrl.stall) begin
            insn       <= if2_insn;
            btb_pred   <= slot_btb;
            id_next_pc <= pc;
        end

    // imem answers only the request in flight.
    `DC_ASSERT(a_imem_answer_expected, !answer || pending)
    // The instruction that enters goes into IF2 at the same edge: nothing to keep elsewhere.
    `DC_ASSERT(a_taken_enters_if2, !taken || !if2_keep)
    // An instruction from the kept line has its word in IF2 at the next clock.
    `DC_ASSERT_NEXT(a_line_take_has_word, line_taken && !ctrl.redirect, slot.valid && !if2_wait)
    // The instruction in IF2 with its word is in ID at the next clock, unless ID stalls or a
    // redirect drops it: the one clock of the register stage.
    `DC_ASSERT_NEXT(a_if2_to_id, to_id.valid && ctrl.run && !ctrl.stall && !ctrl.redirect,
                    fetch.valid && fetch.pc == $past(slot.pc))
    // While ID stalls, the instruction in ID stays: its pc, and its word.
    `DC_ASSERT_NEXT(a_id_held, ctrl.stall && fetch.valid,
                    fetch.valid && $stable(fetch.pc) && $stable(insn))

endmodule

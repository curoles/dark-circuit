/* Mig2 fetch: program counter, branch target buffer and instruction memory requests.
 *
 * Fetch asks imem for the instruction at pc (a request on the imem channel) and keeps one
 * request in flight: it asks when none is pending or its answer comes in this cycle, and only
 * while the instruction can go into IF/ID at once (ID does not stall). The request imem takes
 * goes into IF/ID at that edge; its word comes 1 or more clocks later, and the slot waits in
 * IF/ID until it is here (fetch.valid=0 with bubble imem meanwhile; the word is kept while ID
 * stalls). A request imem does not take is not kept: fetch asks again in the next cycle, for
 * what is right then; imem acts only on a request it takes (an exception to the valid/ready
 * rule 2 of AGENTS.md, see kb rtl/design/mig2/fetch_waits).
 * Reset loads CFG.rst_addr (reset is a jump), then pc advances with every request imem takes.
 * ctrl.redirect=1 loads ctrl.target (taken branch or jump) and drops the request of this
 * cycle (as with a memory of latency 1, its slot is a bubble of reason ctrl.why) and the
 * instruction waiting in IF/ID: the answer of a dropped request is thrown away when it comes.
 * ctrl.run=0 (reset, halt) stops the requests; IF/ID gets fill bubbles. ctrl.stall=1 keeps pc
 * and IF/ID, so the instruction in ID stays for another cycle.
 * The BTB (BranchTargetBuffer) looks up pc in the same cycle: a hit predicted taken loads
 * its target instead of pc + 1 when imem takes the request, without a bubble; a redirect
 * wins over it. What the BTB said goes with the instruction to ID (btb_pred); Mig2Control
 * checks it in ID, updates the BTB from EX (btb_update) and clears a wrong entry from ID
 * (btb_inval). The BTB sees the low btb_index_width + btb_tag_width bits of the word address
 * (Mig2ConfigPkg).
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "dark_circuit_assert.svh"

module Mig2Fetch import Mig2Pkg::*; #(
    parameter mig2_cfg_t CFG = MIG2_CFG   // configuration, see Mig2ConfigPkg
)(
    input  wire         clk,
    input  wire         rst_n,            // synchronous reset, active low
    input  fetch_ctrl_t ctrl,             // run, stall, redirect and target, from Mig2Control
    // Only the low bits of the pcs are used: those the BTB sees.
    /* verilator lint_off UNUSEDSIGNAL */
    input  btb_update_t btb_update,       // a branch or JAL completed in EX: the BTB learns it
    input  btb_inval_t  btb_inval,        // the BTB sent fetch where the insn in ID does not go
    /* verilator lint_on UNUSEDSIGNAL */
    output imem_req_t   imem_req,         // request to imem: valid and word address
    input  imem_rsp_t   imem_rsp,         // imem takes it (ready), the answer (valid, data)
    output fetch_t      fetch,            // the instruction in ID: valid when its word is here
    output insn_t       insn,             // its word
    output btb_pred_t   btb_pred,         // what the BTB said for the instruction in ID
    output wire         id_wait,          // the slot in ID waits for its word from imem
    output wire         id_keep           // IF/ID keeps its slot at the rising edge
);
    localparam iaddr_t RST_PC       = CFG.rst_addr[WIDTH-1:IADDR_START];   // word address
    localparam         BTB_PC_WIDTH = CFG.btb_index_width + CFG.btb_tag_width; // pc bits it sees

    logic      rst;         // reset active
    iaddr_t    pc;          // address fetch asks imem for in this cycle
    logic      taken;       // imem takes the request of this cycle
    logic      pending;     // a request imem took is not answered yet
    logic      drop;        // its answer is thrown away: its slot was dropped
    logic      answer;      // the answer of the pending request comes in this cycle
    logic      got;         // the word of the slot in IF/ID came in an earlier cycle
    logic      have_word;   // the word of the slot is here: kept, or the answer of now
    insn_t     word_q;      // the last answer of imem
    fetch_t    slot;        // IF/ID: the request of the instruction in ID
    logic      predict;     // the BTB sends fetch to its target
    logic      jump;        // load jump_pc: reset, redirect or prediction
    iaddr_t    jump_pc;     // address of the jump
    btb_pred_t btb_d;       // what the BTB says for the request of this cycle
    iaddr_t    btb_target;  // target of the entry of pc; means something only on a hit

    assign rst    = !rst_n;
    assign answer = imem_rsp.valid;

    // @kb: rtl/design/mig2/fetch_waits
    assign imem_req.valid = ctrl.run && !ctrl.stall && (!pending || answer);
    assign imem_req.addr  = pc;
    assign taken          = imem_req.valid && imem_rsp.ready;

    // pc moves on when imem takes its request; a redirect drops the request of this cycle,
    // and with it what the BTB said about it: jump_pc takes ctrl.target first.
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

    // IF/ID keeps its slot while ID stalls, or while the slot waits for its word, unless a
    // redirect or a halt drops it; else it takes the request imem takes now, or a bubble.
    assign have_word = got || (answer && !drop);
    assign id_wait   = slot.valid && !have_word;
    assign id_keep   = ctrl.stall || (id_wait && ctrl.run && !ctrl.redirect);

    fetch_t fetch_d;
    assign fetch_d = '{valid:  taken && !ctrl.redirect,
                       bubble: ctrl.redirect ? ctrl.why : !ctrl.run ? BUBBLE_FILL :
                               taken ? BUBBLE_NONE : BUBBLE_IMEM,
                       pc:     pc};

    Mig2PipeReg #(.T(fetch_t)) u_mig2_pipe_reg_if_id(
        .clk, .rst_n, .stall(id_keep), .flush(1'b0), .why(BUBBLE_NONE), .d(fetch_d),
        .q(slot));

    // IF/ID of what the BTB said: the same moves as the slot; no reset, it means nothing
    // while the slot is a bubble.
    always_ff @(posedge clk)
        if (!id_keep)
            btb_pred <= btb_d;

    // The request in flight and its answer: thrown away when it was taken in a redirect
    // cycle, or when IF/ID drops its slot while it is pending.
    always_ff @(posedge clk)
        if (!rst_n) begin
            pending <= 1'b0;
            drop    <= 1'b0;
            got     <= 1'b0;
        end else begin
            pending <= taken || (pending && !answer);
            drop    <= taken ? ctrl.redirect : pending && !answer && (drop || !id_keep);
            got     <= id_keep && have_word;
        end

    // The word of the instruction in ID: the answer of this cycle, or the last one kept.
    always_ff @(posedge clk)
        if (answer)
            word_q <= imem_rsp.data;

    assign insn  = answer ? imem_rsp.data : word_q;
    assign fetch = '{valid:  slot.valid && have_word,
                     bubble: id_wait ? BUBBLE_IMEM : slot.bubble,
                     pc:     slot.pc};

    // imem answers only the request in flight.
    `DC_ASSERT(a_imem_answer_expected, !answer || pending)
    // The request imem takes goes into IF/ID at the same edge: nothing to keep elsewhere.
    `DC_ASSERT(a_taken_enters_ifid, !taken || !id_keep)

endmodule

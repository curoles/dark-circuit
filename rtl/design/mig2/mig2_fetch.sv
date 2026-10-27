/* Mig2 fetch: program counter, branch target buffer and instruction memory requests.
 *
 * pc is the address requested from imem in this cycle; the instruction comes
 * 1 clock later, together with fetch.valid and fetch.pc for the next stage.
 * Reset loads CFG.rst_addr (reset is a jump), then the PC advances every cycle with
 * ctrl.run=1 and holds with ctrl.run=0. ctrl.redirect=1 loads ctrl.target (taken
 * branch or jump) and drops the request of this cycle: its instruction comes with
 * fetch.valid=0. ctrl.stall=1 keeps everything: pc, the imem output (SimROM and SRAM
 * hold data while en=0) and fetch, so the instruction in ID stays for another cycle.
 * A slot without an instruction carries its reason (bubble_e): ctrl.why for a dropped
 * request, fill when fetch does not run (reset, halt).
 * The BTB (BranchTargetBuffer) looks up pc in the same cycle: a hit predicted taken loads
 * its target instead of pc + 1, without a bubble; a redirect or a stall wins over it.
 * What the BTB said goes with the instruction to ID (btb_pred); Mig2Control checks it in
 * ID, updates the BTB from EX (btb_update) and clears a wrong entry from ID (btb_inval).
 * The BTB sees the low btb_index_width + btb_tag_width bits of the word address
 * (Mig2ConfigPkg).
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
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
    output imem_req_t   imem_req,         // request to imem: enable and word address
    output fetch_t      fetch,            // instruction arriving from imem: valid and pc, to ID
    output btb_pred_t   btb_pred          // what the BTB said for the instruction in ID
);
    localparam iaddr_t RST_PC       = CFG.rst_addr[WIDTH-1:IADDR_START];   // word address
    localparam         BTB_PC_WIDTH = CFG.btb_index_width + CFG.btb_tag_width; // pc bits it sees

    logic      rst;         // reset active
    iaddr_t    pc;          // address requested from imem in this cycle
    logic      advance;     // request the next instruction
    logic      predict;     // the BTB sends fetch to its target
    logic      jump;        // load jump_pc: reset, redirect or prediction
    iaddr_t    jump_pc;     // address of the jump
    btb_pred_t btb_d;       // what the BTB says for the request of this cycle
    iaddr_t    btb_target;  // target of the entry of pc; means something only on a hit

    assign rst     = !rst_n;
    assign advance = ctrl.run && !ctrl.stall;
    // A stall keeps pc, so the same lookup comes again. A redirect drops the request of
    // this cycle, and with it what the BTB said about it: jump_pc takes ctrl.target first.
    assign predict = advance && btb_d.taken;
    assign jump    = rst || ctrl.redirect || predict;
    assign jump_pc = rst ? RST_PC : ctrl.redirect ? ctrl.target : btb_target;

    // @kb: rtl/design/mig2/dropped_next_pc_without_prg_counter
    PrgCounter #(.ADDR_WIDTH(WIDTH), .INSN_SIZE($bits(insn_t) / 8)) u_prg_counter(
        .clk, .en(advance), .jump, .jump_addr(jump_pc), .pc);

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

    assign imem_req.en   = advance;
    assign imem_req.addr = pc;

    // IF/ID: the instruction comes from imem 1 clock after its request; valid=0 when
    // fetch did not run (a fill bubble) or the request was dropped by a redirect.
    fetch_t fetch_d;
    assign fetch_d = '{valid:  ctrl.run && !ctrl.redirect,
                       bubble: ctrl.redirect ? ctrl.why : ctrl.run ? BUBBLE_NONE : BUBBLE_FILL,
                       pc:     pc};

    Mig2PipeReg #(.T(fetch_t)) u_mig2_pipe_reg_if_id(
        .clk, .rst_n, .stall(ctrl.stall), .flush(1'b0), .why(BUBBLE_NONE), .d(fetch_d),
        .q(fetch));

    // IF/ID of what the BTB said: the same stall as the instruction; no reset, it means
    // nothing while fetch.valid=0.
    always_ff @(posedge clk)
        if (!ctrl.stall)
            btb_pred <= btb_d;

endmodule

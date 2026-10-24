/* Mig2 fetch: program counter and instruction memory requests.
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
    output imem_req_t   imem_req,         // request to imem: enable and word address
    output fetch_t      fetch             // instruction arriving from imem: valid and pc, to ID
);
    localparam iaddr_t RST_PC = CFG.rst_addr[WIDTH-1:IADDR_START];   // word address

    logic   rst;        // reset active
    iaddr_t pc;         // address requested from imem in this cycle
    logic   advance;    // request the next instruction
    logic   jump;       // load jump_pc: reset or redirect
    iaddr_t jump_pc;    // address of the jump

    assign rst     = !rst_n;
    assign advance = ctrl.run && !ctrl.stall;
    assign jump    = rst || ctrl.redirect;
    assign jump_pc = rst ? RST_PC : ctrl.target;

    PrgCounter #(.ADDR_WIDTH(WIDTH), .INSN_SIZE($bits(insn_t) / 8)) u_prg_counter(
        .clk, .en(advance), .jump, .jump_addr(jump_pc), .pc);

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

endmodule

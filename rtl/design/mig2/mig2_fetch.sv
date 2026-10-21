/* Mig2 fetch: program counter and instruction memory requests.
 *
 * pc is the address requested from imem in this cycle; the instruction comes
 * 1 clock later, together with fetch.valid and fetch.pc for the next stage.
 * Reset loads CFG.rst_addr (reset is a jump), then the PC advances every cycle with
 * ctrl.run=1 and holds with ctrl.run=0. ctrl.redirect=1 loads ctrl.target (taken
 * branch or jump) and drops the request of this cycle: its instruction comes with
 * fetch.valid=0. ctrl.stall=1 keeps everything: pc, the imem output (SimROM and SRAM
 * hold data while en=0) and fetch, so the instruction in ID stays for another cycle.
 */
module Mig2Fetch import Mig2Pkg::*; #(
    parameter mig2_cfg_t CFG = MIG2_CFG   // configuration, see Mig2ConfigPkg
)(
    input  wire         clk,
    input  wire         rst_n,            // synchronous reset, active low
    input  fetch_ctrl_t ctrl,
    output imem_req_t   imem_req,
    output fetch_t      fetch
);
    localparam iaddr_t RST_PC = CFG.rst_addr[WIDTH-1:IADDR_START];

    iaddr_t pc;
    logic   advance;   // request the next instruction
    logic   jump;
    iaddr_t jump_pc;

    assign advance = ctrl.run && !ctrl.stall;

    assign jump    = !rst_n || ctrl.redirect;
    assign jump_pc = !rst_n ? RST_PC : ctrl.target;

    PrgCounter #(.ADDR_WIDTH(WIDTH), .INSN_SIZE(INSN_WIDTH / 8)) u_prg_counter(
        .clk(clk), .en(advance), .jump(jump), .jump_addr(jump_pc), .pc(pc));

    assign imem_req.en   = advance;
    assign imem_req.addr = pc;

    // IF/ID: the instruction comes from imem 1 clock after its request; valid=0 when
    // fetch did not run or the request was dropped by a redirect.
    fetch_t fetch_d;
    assign fetch_d.valid = ctrl.run && !ctrl.redirect;
    assign fetch_d.pc    = pc;

    Mig2PipeReg #(.T(fetch_t)) u_mig2_pipe_reg_if_id(
        .clk, .rst_n, .stall(ctrl.stall), .flush(1'b0), .d(fetch_d), .q(fetch));

endmodule

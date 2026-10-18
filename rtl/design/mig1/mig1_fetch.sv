/* Mig1 fetch: program counter and instruction memory requests.
 *
 * pc is the address requested from imem in this cycle; the instruction comes
 * 1 clock later, together with fetch.valid and fetch.pc for the next stage.
 * Reset loads RST_ADDR (reset is a jump), then the PC advances every cycle with
 * ctrl.run=1 and holds with ctrl.run=0. ctrl.redirect=1 loads ctrl.target (taken
 * branch or jump) and drops the request of this cycle: its instruction comes with
 * fetch.valid=0. ctrl.stall=1 keeps everything: pc, the imem output (SimROM and SRAM
 * hold data while en=0) and fetch, so the instruction in ID stays for another cycle.
 */
module Mig1Fetch import Mig1Pkg::*; #(
    parameter RST_ADDR = MIG1_RST_ADDR    // PC after reset, byte address
)(
    input  wire         clk,
    input  wire         rst_n,            // synchronous reset, active low
    input  fetch_ctrl_t ctrl,
    output imem_req_t   imem_req,
    output fetch_t      fetch
);
    localparam iaddr_t RST_PC = RST_ADDR[WIDTH-1:IADDR_START];

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

    always_ff @(posedge clk)
        if (!rst_n || !ctrl.stall) begin
            fetch.valid <= rst_n && ctrl.run && !ctrl.redirect;
            fetch.pc    <= pc;
        end

endmodule

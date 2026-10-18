/* Mig1 fetch: program counter and instruction memory requests.
 *
 * pc is the address requested from imem in this cycle; the instruction comes
 * 1 clock later, together with fetch.valid and fetch.pc for the next stage.
 * Reset loads RST_ADDR (reset is a jump), then the PC advances every cycle with
 * ctrl.run=1 and holds with ctrl.run=0. ctrl.redirect=1 loads ctrl.target (taken
 * branch or jump) and drops the request of this cycle: its instruction comes with
 * fetch.valid=0.
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
    logic   jump;
    iaddr_t jump_pc;

    assign jump    = !rst_n || ctrl.redirect;
    assign jump_pc = !rst_n ? RST_PC : ctrl.target;

    PrgCounter #(.ADDR_WIDTH(WIDTH), .INSN_SIZE(INSN_WIDTH / 8)) u_prg_counter(
        .clk(clk), .en(ctrl.run), .jump(jump), .jump_addr(jump_pc), .pc(pc));

    assign imem_req.en   = ctrl.run;
    assign imem_req.addr = pc;

    always_ff @(posedge clk) begin
        fetch.valid <= rst_n && ctrl.run && !ctrl.redirect;
        fetch.pc    <= pc;
    end

endmodule

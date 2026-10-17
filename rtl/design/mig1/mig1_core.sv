/* Mig1 RISC-V RV32I core, synthesizable, memories are outside.
 *
 * Instruction fetch and data access have 1 clock read latency, like SimROM,
 * SimRAM, SRAM and FPGA block RAM. The core stops (halt=1) on EBREAK, ECALL or an
 * illegal instruction; illegal=1 tells that it can not continue. While halted,
 * the debug port reads and writes registers, and resume continues after EBREAK.
 *
 * TODO: the core; for now the ports only, the core does nothing.
 */
module Mig1Core import Mig1Pkg::*; #(
    parameter RST_ADDR = MIG1_RST_ADDR     // PC after reset, byte address
)(
    input  wire       clk,
    input  wire       rst_n,               // synchronous reset, active low

    output imem_req_t imem_req,
    input  imem_rsp_t imem_rsp,
    output dmem_req_t dmem_req,
    input  dmem_rsp_t dmem_rsp,

    output wire       halt,                // core stopped: EBREAK, ECALL or illegal
    output wire       illegal,             // stopped by ECALL, illegal instruction
                                           // or jump to address not divisible by 4
    output retire_t   retire,

    input  dbg_req_t  dbg_req,
    output dbg_rsp_t  dbg_rsp
);

    // TODO: remove with the core, inputs and RST_ADDR are not used by the stub.
    /* verilator lint_off UNUSEDSIGNAL */
    /* verilator lint_off UNUSEDPARAM */
    wire stub_unused = &{1'b0, clk, rst_n, imem_rsp, dmem_rsp, dbg_req, RST_ADDR};
    /* verilator lint_on UNUSEDPARAM */
    /* verilator lint_on UNUSEDSIGNAL */

    assign imem_req = '0;
    assign dmem_req = '0;
    assign halt     = 1'b0;
    assign illegal  = 1'b0;
    assign retire   = '0;
    assign dbg_rsp  = '0;

endmodule

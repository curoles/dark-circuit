/* Mig6 PE (processing element), for simulation: one Mig6Core and its local memory.
 *
 * A prototype (rtl/design/mig6/README.md): for now a PE is its core and its local memory,
 * the code and data of the program, private to the core (the shared memory comes with the
 * network interface, a later chunk). The local memory is a SimLatencyRAM behind the core's
 * memory port (latency 1, always ready), as Mig3Cpu's memory without its devices; the core's
 * caches are in front of it, so it is not a scratchpad (a memory without caches before it).
 * HART_ID is the hart's ID, what mhartid reads, one per PE; MY_PE_GRID_X and MY_PE_GRID_Y
 * are the PE's node in the mesh (Mig6NocPkg: PE p at (p % MESH_X, p / MESH_X)), what
 * mnodeid reads, and later its network interface's coordinates. The local memory has
 * 1 << CFG.mem_addr_width bytes; the core address bits above them are ignored, so addresses
 * wrap around.
 *
 * Not yet in a PE, each checked by an assertion: requests to the I/O region (no devices),
 * and atomics (no AtomicUnit in front of the local memory; LR/SC are the core's own).
 *
 *   Mig6Core --mem_req--> u_local_mem (SimLatencyRAM)
 *            <--mem_rsp--
 *
 * load() puts the hex image (objcopy -O verilog, see sw/riscv/mig6.ld) into the local
 * memory; peek() reads a byte of it, for the testbench's semihosting.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */

`include "dark_circuit_assert.svh"

module Mig6Pe import Mig6Pkg::*; #(
    parameter mig6_cfg_t CFG     = MIG6_CFG,    // configuration, see Mig6ConfigPkg
    parameter word_t     HART_ID = '0,          // the hart's ID: mhartid
    // Its node in the mesh: mnodeid, and its network interface's coordinates.
    parameter logic [Mig6NocPkg::X_WIDTH-1:0] MY_PE_GRID_X = '0,
    parameter logic [Mig6NocPkg::Y_WIDTH-1:0] MY_PE_GRID_Y = '0
)(
    input  wire         clk,
    input  wire         rst_n,                  // synchronous reset, active low
    output wire         halt,                   // core halted at EBREAK, see Mig6Core
    output retire_t     retire,                 // for trace in testbench
    output pipe_trace_t pipe_trace,             // pipeline view for testbench
    input  dbg_req_t    dbg_req,                // debug, used while halted
    output dbg_rsp_t    dbg_rsp
);
    localparam MEM_ADDR_WIDTH = CFG.mem_addr_width;     // local memory: 1 << it bytes

    // Not used: the size (the local memory moves lines with strobes) and a CBO's operation
    // (it ends here, the local memory holds no lines).
    /* verilator lint_off UNUSEDSIGNAL */
    mem_req_t mem_req;
    /* verilator lint_on UNUSEDSIGNAL */
    mem_rsp_t mem_rsp;

    Mig6Core #(.CFG(CFG), .HART_ID(HART_ID), .MY_PE_GRID_X(8'(MY_PE_GRID_X)),
               .MY_PE_GRID_Y(8'(MY_PE_GRID_Y))) u_mig6_core(
        .clk, .rst_n, .mem_req, .mem_rsp, .uncached(1'b0), .meip(1'b0), .halt, .retire,
        .pipe_trace, .dbg_req, .dbg_rsp);

    // The local memory, code and data; latency 1, always ready.
    SimLatencyRAM #(.DATA_SIZE(LINE_SIZE), .ADDR_WIDTH(MEM_ADDR_WIDTH),
                    .READY_PERCENT(100), .FAST_PERCENT(100), .FAST_MIN(1), .FAST_MAX(1),
                    .MAX_PENDING(1)) u_local_mem(
        .clk, .rst_n,
        .req_valid(mem_req.valid), .req_ready(mem_rsp.ready), .req_we(mem_req.we),
        .req_addr({mem_req.addr[MEM_ADDR_WIDTH-1:LINE_START], {LINE_START{1'b0}}}),
        .req_wdata(mem_req.wdata), .req_wstrb(mem_req.wstrb),
        .rsp_valid(mem_rsp.valid), .rsp_data(mem_rsp.data));

    // Not in a PE yet: devices in the I/O region, atomics in front of the local memory.
    `DC_ASSERT(a_no_io, !(mem_req.valid &&
        (mem_req.addr >> CFG.io_addr_width) == (WIDTH'(CFG.io_base) >> CFG.io_addr_width)))
    `DC_ASSERT(a_no_atomic, !(mem_req.valid && AtomicPkg::is_atomic(mem_req.atop)))

    // Load the hex image into the local memory, returns 1 when it is loaded.
    function automatic int load(string hex);
        return u_local_mem.load(hex, u_local_mem.VLOG_HEX_FORMAT);
    endfunction

    // Byte at address a of the local memory (the low MEM_ADDR_WIDTH bits: addresses wrap).
    function automatic logic [7:0] peek(input logic [MEM_ADDR_WIDTH-1:0] a);
        return u_local_mem.peek(a);
    endfunction

endmodule
